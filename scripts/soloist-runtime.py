#!/usr/bin/env python3
"""User-owned Soloist installation. Secrets travel only through keyring/stdin."""

import fcntl
import hashlib
import http.client
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
import urllib.error
import urllib.request
import zlib
from pathlib import Path


def xdg_path(variable, fallback):
    # The XDG spec says relative values are invalid and must be ignored.
    value = os.environ.get(variable, "")
    return Path(value) if value.startswith("/") else Path.home() / fallback


RUNTIME = Path.home() / ".local/lib/omaspotify"
CONFIG = xdg_path("XDG_CONFIG_HOME", ".config")
STATE = xdg_path("XDG_STATE_HOME", ".local/state") / "omaspotify/soloist"
CACHE = xdg_path("XDG_CACHE_HOME", ".cache") / "omaspotify/soloist"
UNIT = "omaspotify-soloist.service"
UPDATE_UNIT = "omaspotify-soloist-update.service"
TIMER_UNIT = "omaspotify-soloist-update.timer"
KEY = ["service", "omaspotify", "kind", "soloist-api-key"]
MAX_ARCHIVE = 80 * 1024 * 1024
MAX_BINARY = 160 * 1024 * 1024
BUILD_LIFETIME = 90 * 86400
RENEW_AFTER = 75 * 86400
# Must stay under the backend's startup deadline, or a slow download is killed
# part way and starts again from nothing on every restart.
START_DOWNLOAD_SECONDS = 75
INSTALL_DOWNLOAD_SECONDS = 600
# The backend turns these into errors the UI can explain, and systemd does not retry them.
EXIT_MISSING_KEY = 77
EXIT_EXPIRED = 75


class StartFailure(ValueError):
    """A reason playback cannot start that restarting would not fix."""

    def __init__(self, message, code):
        super().__init__(message)
        self.code = code


DOWNLOAD_FAILURES = (
    tarfile.TarError,
    EOFError,
    KeyError,
    zlib.error,
    http.client.HTTPException,
    urllib.error.URLError,
)


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
        metadata = json.loads((RUNTIME / "soloist-build.json").read_text())
    except (OSError, ValueError):
        return {}
    return metadata if isinstance(metadata, dict) else {}


def build_time():
    built_at = installed_metadata().get("built_at")
    return built_at if isinstance(built_at, int) and not isinstance(built_at, bool) else 0


def lock_for(lock, seconds):
    """Wait for the install lock, so a stalled renewal cannot block playback forever."""
    deadline = time.monotonic() + seconds
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            if time.monotonic() >= deadline:
                raise ValueError("Another Soloist update is still running") from None
            time.sleep(0.5)


def download_archive(url, destination, deadline):
    with urllib.request.urlopen(url, timeout=60) as response, destination.open("wb") as output:
        # No executable downloads may redirect away from Spotify's CDN.
        if not response.url.startswith("https://soloist-builds.spotifycdn.com/"):
            raise ValueError("Unexpected Soloist download destination")
        size = 0
        while chunk := response.read(65536):
            size += len(chunk)
            if size > MAX_ARCHIVE:
                raise ValueError("Soloist archive exceeds the download limit")
            if time.monotonic() > deadline:
                raise ValueError("Soloist download took too long")
            output.write(chunk)


def extract_executable(archive, destination):
    with tarfile.open(archive, "r:gz") as bundle:
        # Walk rather than look up by name, which would inflate the whole archive.
        for member in bundle:
            if member.name == "soloist":
                break
            if bundle.offset > MAX_BINARY:
                raise ValueError("Soloist archive has an invalid executable")
        else:
            raise ValueError("Soloist archive has no executable")
        if not member.isfile() or not 0 < member.size <= MAX_BINARY:
            raise ValueError("Soloist archive has an invalid executable")
        with bundle.extractfile(member) as source, destination.open("wb") as output:
            shutil.copyfileobj(source, output)
        # No archive paths, links, scripts, or permissions are extracted.


def sweep_interrupted_downloads():
    # A killed download cannot clean up after itself. Caller holds the install lock.
    for leftover in RUNTIME.glob(".soloist-*"):
        if leftover.is_dir() and not leftover.is_symlink():
            shutil.rmtree(leftover, ignore_errors=True)


def update(force=False, deadline=INSTALL_DOWNLOAD_SECONDS):
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (RUNTIME / ".soloist-install.lock").open("a") as lock:
        lock_for(lock, deadline)
        old_built_at = build_time()
        if (
            not force
            and (RUNTIME / "soloist").is_file()
            and old_built_at + RENEW_AFTER > time.time()
        ):
            return
        sweep_interrupted_downloads()
        arch = {"x86_64": "x86_64", "aarch64": "arm64", "armv7l": "arm32"}.get(
            platform.machine()
        )
        if not arch:
            raise ValueError("This architecture is not supported by Spotify Soloist")
        url = f"https://soloist-builds.spotifycdn.com/soloist_release_{arch}.tar.gz"
        with tempfile.TemporaryDirectory(prefix=".soloist-", dir=RUNTIME) as temporary:
            directory = Path(temporary)
            archive = directory / "download.tar.gz"
            candidate = directory / "soloist"
            try:
                download_archive(url, archive, time.monotonic() + deadline)
                extract_executable(archive, candidate)
            except DOWNLOAD_FAILURES as error:
                raise ValueError("Soloist download was invalid") from error
            candidate.chmod(0o755)
            version = run([str(candidate), "--version"])
            if version.returncode:
                raise ValueError("The downloaded Soloist build could not run")
            built_at = build_timestamp(version.stdout)
            if built_at + BUILD_LIFETIME <= time.time():
                raise ValueError("Spotify supplied an expired Soloist build")
            if built_at < old_built_at:
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


def unit_files(backend, config):
    hardening = """UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
LimitCORE=0
LockPersonality=true
RestrictSUIDSGID=true
RestrictNamespaces=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
"""
    helper = systemd_quote(RUNTIME / "soloist-runtime.py")
    return {
        UNIT: f"""[Unit]
Description=OmaSpotify with Spotify Soloist
After=graphical-session.target sound.target
Conflicts=omaspotify.service
StartLimitIntervalSec=300
StartLimitBurst=3

[Service]
ExecStart={systemd_quote(backend)} --soloist --config-path={systemd_quote(config)}
Restart=on-failure
RestartSec=5
RestartPreventExitStatus=75 77 78
TimeoutStopSec=5
{hardening}""",
        UPDATE_UNIT: f"""[Unit]
Description=Renew expiring Spotify Soloist build

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 {helper} update
TimeoutStartSec=15min
ProtectHome=read-only
ReadWritePaths={systemd_quote(RUNTIME)}
{hardening}""",
        TIMER_UNIT: """[Unit]
Description=Check Spotify Soloist build lifetime daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
""",
    }


def write_atomically(path, content, mode):
    """Write only what changed. Returns whether the file on disk was replaced."""
    try:
        if path.read_bytes() == content and (path.stat().st_mode & 0o777) == mode:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise
    return True


def sync():
    """Bring the installed helper and units up to this plugin version, offline.

    A plugin update replaces this file but not the copy the service runs, and
    Install / repair is only offered while playback is broken.
    """
    if not (RUNTIME / "soloist").is_file():
        return False
    units = CONFIG / "systemd/user"
    changed = False
    source = Path(__file__).read_bytes()
    destination = RUNTIME / "soloist-runtime.py"
    if Path(__file__).resolve() != destination.resolve():
        changed = write_atomically(destination, source, 0o755)
    files = unit_files(RUNTIME / "omaspotify-backend", CONFIG / "omaspotify/playback.conf")
    for name, content in files.items():
        changed = write_atomically(units / name, content.encode(), 0o600) or changed
    if changed and run(["systemctl", "--user", "daemon-reload"]).returncode:
        raise ValueError("Could not register Soloist's user service and update timer")
    return changed


def install():
    existing = shutil.which("soloist")
    if existing and Path(existing).resolve() != (RUNTIME / "soloist").resolve():
        raise ValueError(
            "Soloist is already installed elsewhere; choose one installation source first"
        )
    update()
    sync()
    for args in (["daemon-reload"], ["enable", "--now", TIMER_UNIT]):
        if run(["systemctl", "--user", *args]).returncode:
            raise ValueError(
                "Could not register Soloist's user service and update timer"
            )


def backend_current():
    """Whether the installed backend was built from this plugin's source."""
    fingerprint = Path(__file__).resolve().parent / "backend-source-id.sh"
    if not fingerprint.is_file():
        return True
    try:
        recorded = (RUNTIME / "backend-source.sha256").read_text().strip()
    except OSError:
        return False
    result = run([str(fingerprint)])
    return result.returncode == 0 and result.stdout.strip() == recorded


def status():
    info = installed_metadata()
    built_at = build_time()
    result = {
        "installed": (RUNTIME / "soloist").is_file(),
        "unit": (CONFIG / "systemd/user" / UNIT).is_file(),
        "key": None if "--no-key" in sys.argv else bool(key()),
        "paired": (STATE / "paired").is_file(),
        "running": run(["systemctl", "--user", "is-active", "--quiet", UNIT]).returncode
        == 0,
        "daysRemaining": max(0, int((built_at + BUILD_LIFETIME - time.time()) / 86400)),
        "version": info.get("version", ""),
    }
    if "--backend" in sys.argv:
        result["backendCurrent"] = backend_current()
    return result


def initial_volume_args():
    try:
        with (STATE / "volume").open() as saved:
            value = int(saved.read(64).strip())
        if 0 <= value <= 100:
            return ["--initial-volume", str(value)]
    except (OSError, ValueError):
        pass
    return []


def ensure_runnable_build():
    """Download only when nothing here can run; otherwise renewal never delays music."""
    now = time.time()
    built_at = build_time()
    if (RUNTIME / "soloist").is_file() and built_at + BUILD_LIFETIME > now:
        if built_at + RENEW_AFTER <= now:
            try:
                run(["systemctl", "--user", "start", "--no-block", UPDATE_UNIT])
            except (OSError, subprocess.SubprocessError):
                pass
        return
    # Updates cannot replace the key or pairing.
    try:
        update(deadline=START_DOWNLOAD_SECONDS)
    except (OSError, ValueError, subprocess.SubprocessError):
        raise StartFailure(
            "Soloist has expired and could not be updated", EXIT_EXPIRED
        ) from None


def clear_key():
    # Exit 1 means nothing matched only when nothing was said on stderr; an
    # unreachable keyring also exits 1, and the key would still be there.
    result = run(["secret-tool", "clear", *KEY])
    return result.returncode == 0 or (result.returncode == 1 and not result.stderr.strip())


def start_receiver():
    ensure_runnable_build()
    token = key()
    if not token:
        raise StartFailure(
            "Add your Spotify Soloist API key in OmaSpotify Settings", EXIT_MISSING_KEY
        )
    for directory in (STATE, CACHE):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
    name = sys.argv[2] if len(sys.argv) > 2 else "OmaSpotify"
    # Our own errors go to the journal, but Soloist's output stays out of it because
    # its command line holds the key.
    silence = os.open(os.devnull, os.O_WRONLY)
    os.dup2(silence, sys.stderr.fileno())
    os.close(silence)
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
            *initial_volume_args(),
        ],
    )


def main():
    os.umask(0o077)
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "install":
        install()
    elif action == "update":
        update(force="--force" in sys.argv[2:])
    elif action == "sync":
        sync()
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
        if not clear_key():
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
    except StartFailure as error:
        print(error, file=sys.stderr)
        sys.exit(error.code)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Never print subprocess commands, outputs or exception details containing keys.
        print(
            str(error)
            if isinstance(error, ValueError)
            else "Soloist operation failed; check the installation and network",
            file=sys.stderr,
        )
        sys.exit(1)
