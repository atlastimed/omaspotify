#!/usr/bin/env python3
"""User-owned Soloist installation. Secrets travel only through keyring/stdin."""

import fcntl
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path

RUNTIME = Path.home() / ".local/lib/omaspotify"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
STATE = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    / "omaspotify/soloist"
)
CACHE = (
    Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    / "omaspotify/soloist"
)
UNIT = "omaspotify-soloist.service"
KEY = ["service", "omaspotify", "kind", "soloist-api-key"]
MAX_ARCHIVE = 80 * 1024 * 1024
MAX_BINARY = 160 * 1024 * 1024
BUILD_LIFETIME = 90 * 86400


def run(args, **kwargs):
    return subprocess.run(
        args, check=False, capture_output=True, text=True, timeout=15, **kwargs
    )


def key():
    return run(["secret-tool", "lookup", *KEY]).stdout.strip()


def build_timestamp(output):
    match = re.search(r"\bbuild (\d{10})\b", output)
    if not match:
        raise ValueError("Soloist did not report a recognized build date")
    timestamp = int(match[1])
    if timestamp > time.time() + 86400:
        raise ValueError("Soloist reported a future build date")
    return timestamp


def installed_metadata():
    try:
        return json.loads((RUNTIME / "soloist-build.json").read_text())
    except (OSError, ValueError):
        return {}


def update(force=False):
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (RUNTIME / ".soloist-install.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = installed_metadata()
        if (
            not force
            and (RUNTIME / "soloist").is_file()
            and old.get("built_at", 0) + 75 * 86400 > time.time()
        ):
            return
        arch = {"x86_64": "x86_64", "aarch64": "arm64", "armv7l": "arm32"}.get(
            platform.machine()
        )
        if not arch:
            raise ValueError("This architecture is not supported by Spotify Soloist")
        url = f"https://soloist-builds.spotifycdn.com/soloist_release_{arch}.tar.gz"
        with tempfile.TemporaryDirectory(prefix=".soloist-", dir=RUNTIME) as temporary:
            directory = Path(temporary)
            archive = directory / "download.tar.gz"
            with (
                urllib.request.urlopen(url, timeout=60) as response,
                archive.open("wb") as output,
            ):
                # No executable downloads may redirect away from Spotify's CDN.
                if not response.url.startswith(
                    "https://soloist-builds.spotifycdn.com/"
                ):
                    raise ValueError("Unexpected Soloist download destination")
                size = 0
                while chunk := response.read(65536):
                    size += len(chunk)
                    if size > MAX_ARCHIVE:
                        raise ValueError("Soloist archive exceeds the download limit")
                    output.write(chunk)
            candidate = directory / "soloist"
            with tarfile.open(archive, "r:gz") as bundle:
                member = bundle.getmember("soloist")
                if not member.isfile() or not 0 < member.size <= MAX_BINARY:
                    raise ValueError("Soloist archive has an invalid executable")
                with (
                    bundle.extractfile(member) as source,
                    candidate.open("wb") as output,
                ):
                    shutil.copyfileobj(source, output)
                # No archive paths, links, scripts, or permissions are extracted.
            candidate.chmod(0o755)
            version = run([str(candidate), "--version"])
            if version.returncode:
                raise ValueError("The downloaded Soloist build could not run")
            built_at = build_timestamp(version.stdout)
            if built_at + BUILD_LIFETIME <= time.time():
                raise ValueError("Spotify supplied an expired Soloist build")
            if built_at < old.get("built_at", 0):
                raise ValueError("Refusing to replace Soloist with an older build")
            metadata = {
                "built_at": built_at,
                "source": url,
                "sha256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
                "version": version.stdout.strip()[:256],
            }
            staged_metadata = directory / "build.json"
            staged_metadata.write_text(json.dumps(metadata))
            os.replace(candidate, RUNTIME / "soloist")
            os.replace(staged_metadata, RUNTIME / "soloist-build.json")
            # Running playback keeps its original inode; the next start uses the new build.


def systemd_quote(path):
    return (
        '"'
        + str(path).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
        + '"'
    )


def install():
    existing = shutil.which("soloist")
    if existing and Path(existing).resolve() != (RUNTIME / "soloist").resolve():
        raise ValueError(
            "Soloist is already installed elsewhere; choose one installation source first"
        )
    update()
    destination = RUNTIME / "soloist-runtime.py"
    if Path(__file__).resolve() != destination.resolve():
        shutil.copyfile(__file__, destination)
        destination.chmod(0o755)
    units = CONFIG / "systemd/user"
    units.mkdir(parents=True, exist_ok=True)
    backend = systemd_quote(RUNTIME / "omaspotify-backend")
    config = systemd_quote(CONFIG / "omaspotify/playback.conf")
    (units / UNIT).write_text(f"""[Unit]
Description=OmaSpotify with Spotify Soloist
After=graphical-session.target sound.target
Conflicts=omaspotify.service
StartLimitIntervalSec=300
StartLimitBurst=3

[Service]
ExecStart={backend} --soloist --config-path={config}
Restart=on-failure
RestartSec=5
RestartPreventExitStatus=75 77 78
TimeoutStopSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
""")
    (units / "omaspotify-soloist-update.service").write_text(f"""[Unit]
Description=Renew expiring Spotify Soloist build

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 {systemd_quote(destination)} update
UMask=0077
NoNewPrivileges=true
""")
    (units / "omaspotify-soloist-update.timer").write_text("""[Unit]
Description=Check Spotify Soloist build lifetime daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
""")
    for args in (
        ["daemon-reload"],
        ["enable", "--now", "omaspotify-soloist-update.timer"],
    ):
        if run(["systemctl", "--user", *args]).returncode:
            raise ValueError(
                "Could not register Soloist's user service and update timer"
            )


def status():
    info = installed_metadata()
    built_at = info.get("built_at", 0)
    return {
        "installed": (RUNTIME / "soloist").is_file(),
        "unit": (CONFIG / "systemd/user" / UNIT).is_file(),
        "key": None if "--no-key" in sys.argv else bool(key()),
        "paired": (STATE / "paired").is_file(),
        "running": run(["systemctl", "--user", "is-active", "--quiet", UNIT]).returncode
        == 0,
        "daysRemaining": max(0, int((built_at + BUILD_LIFETIME - time.time()) / 86400)),
        "version": info.get("version", ""),
    }


def start_receiver():
    # Updates cannot replace the key or pairing. Failed renewal can use a still-valid build.
    try:
        update()
    except (OSError, ValueError, subprocess.SubprocessError):
        if installed_metadata().get("built_at", 0) + BUILD_LIFETIME <= time.time():
            raise ValueError("Soloist has expired and could not be updated") from None
    token = key()
    if not token:
        raise ValueError("Add your Spotify Soloist API key in OmaSpotify Settings")
    for directory in (STATE, CACHE):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
    name = sys.argv[2] if len(sys.argv) > 2 else "OmaSpotify"
    os.execv(
        str(RUNTIME / "soloist"),
        [
            "soloist",
            "--device-name",
            name,
            "--api-key",
            token,
            "--data-dir",
            str(STATE),
            "--cache-dir",
            str(CACHE),
            "--cache-size",
            "512",
            "--ws",
            "127.0.0.1:0",
        ],
    )


def main():
    os.umask(0o077)
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "install":
        install()
    elif action == "update":
        update(force="--force" in sys.argv[2:])
    elif action == "run":
        start_receiver()
    elif action == "status":
        print(json.dumps(status()))
    elif action == "save-key":
        token = sys.stdin.read(8193).strip()
        if not 16 <= len(token) <= 8192 or any(c.isspace() for c in token):
            raise ValueError("Enter a valid Soloist API key")
        if run(
            ["secret-tool", "store", "--label=OmaSpotify Soloist", *KEY], input=token
        ).returncode:
            raise ValueError("Could not save the Soloist key in your desktop keyring")
    elif action in ("start", "stop"):
        if action == "start":
            run(["systemctl", "--user", "reset-failed", UNIT])
        if run(["systemctl", "--user", action, UNIT]).returncode:
            raise ValueError(f"Could not {action} Soloist")
    elif action == "clear":
        run(["systemctl", "--user", "stop", UNIT])
        if run(["secret-tool", "clear", *KEY]).returncode not in (0, 1):
            raise ValueError("Could not clear the Soloist key")
        # This directory belongs exclusively to this integration, never ~/.local/share/soloist.
        if STATE.is_symlink():
            raise ValueError("Refusing to clear a linked Soloist state directory")
        if STATE.exists():
            shutil.rmtree(STATE)
    else:
        raise ValueError("Unknown Soloist runtime action")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Never print subprocess commands, outputs or exception details containing keys.
        print(
            str(error)
            if isinstance(error, ValueError)
            else "Soloist operation failed; check the installation and network",
            file=sys.stderr,
        )
        sys.exit(1)
