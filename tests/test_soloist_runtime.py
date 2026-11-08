#!/usr/bin/env python3
"""Installer failure and secret boundaries, without downloads or real keyring access."""

import importlib.util
import io
import json
import subprocess
import tarfile
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "runtime", Path(__file__).parents[1] / "scripts/soloist-runtime.py"
)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class Response(io.BytesIO):
    url = "https://soloist-builds.spotifycdn.com/soloist_release_x86_64.tar.gz"


def archive(link=False):
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode="w:gz") as bundle:
        entry = tarfile.TarInfo("soloist")
        if link:
            entry.type = tarfile.SYMTYPE
            entry.linkname = "/etc/passwd"
        else:
            entry.size = 4
        bundle.addfile(entry, None if link else io.BytesIO(b"test"))
        # Extra archive paths must never be extracted.
        escape = tarfile.TarInfo("../escaped")
        escape.size = 4
        bundle.addfile(escape, io.BytesIO(b"oops"))
    return result.getvalue()


def renamed_archive():
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode="w:gz") as bundle:
        entry = tarfile.TarInfo("soloist-renamed")
        entry.size = 4
        bundle.addfile(entry, io.BytesIO(b"test"))
    return result.getvalue()


class SoloistRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.patch = patch.object(runtime, "RUNTIME", self.root / "runtime")
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_install_only_executable_and_record_exact_source(self):
        stamp = int(time.time()) - 100
        with (
            patch.object(
                runtime.urllib.request, "urlopen", return_value=Response(archive())
            ),
            patch.object(
                runtime,
                "run",
                return_value=subprocess.CompletedProcess(
                    [], 0, f"soloist 1.0 build {stamp} (linux/x86_64)", ""
                ),
            ),
        ):
            runtime.update()

        self.assertEqual((runtime.RUNTIME / "soloist").read_bytes(), b"test")
        self.assertFalse((runtime.RUNTIME / "escaped").exists())
        metadata = runtime.installed_metadata()
        self.assertEqual(metadata["built_at"], stamp)
        self.assertEqual(len(metadata["sha256"]), 64)
        with patch.object(
            runtime.urllib.request,
            "urlopen",
            side_effect=AssertionError("fresh build should not download"),
        ):
            runtime.update()

    def test_restart_restores_volume_including_mute_and_rejects_bad_state(self):
        with patch.object(runtime, "STATE", self.root):
            self.assertEqual(runtime.initial_volume_args(), [])
            for value, expected in [("0", "0"), ("83\n", "83"), ("100", "100")]:
                (self.root / "volume").write_text(value)
                self.assertEqual(runtime.initial_volume_args(), ["--initial-volume", expected])
            for value in ("-1", "101", "nan", "--verbose", ""):
                (self.root / "volume").write_text(value)
                self.assertEqual(runtime.initial_volume_args(), [])

    def test_symlink_executable_rejected_without_replacing_old_build(self):
        runtime.RUNTIME.mkdir()
        (runtime.RUNTIME / "soloist").write_bytes(b"old")
        with patch.object(
            runtime.urllib.request, "urlopen", return_value=Response(archive(True))
        ), self.assertRaises(ValueError):
            runtime.update(True)
        self.assertEqual((runtime.RUNTIME / "soloist").read_bytes(), b"old")

    def test_expired_download_does_not_replace_working_binary(self):
        runtime.RUNTIME.mkdir()
        (runtime.RUNTIME / "soloist").write_bytes(b"old")
        expired = int(time.time()) - 91 * 86400
        with (
            patch.object(
                runtime.urllib.request, "urlopen", return_value=Response(archive())
            ),
            patch.object(
                runtime,
                "run",
                return_value=subprocess.CompletedProcess(
                    [], 0, f"soloist build {expired}", ""
                ),
            ),self.assertRaises(ValueError)
        ):
            runtime.update(True)
        self.assertEqual((runtime.RUNTIME / "soloist").read_bytes(), b"old")

    def test_corrupt_download_is_a_clean_failure_that_keeps_the_old_build(self):
        runtime.RUNTIME.mkdir()
        (runtime.RUNTIME / "soloist").write_bytes(b"old")
        good = archive()
        for body in (b"not a gzip stream", good[: len(good) // 2], renamed_archive()):
            with patch.object(
                runtime.urllib.request, "urlopen", return_value=Response(body)
            ), self.assertRaises(ValueError):
                runtime.update(True)
            self.assertEqual((runtime.RUNTIME / "soloist").read_bytes(), b"old")

    def test_a_download_that_outlives_its_deadline_gives_up(self):
        runtime.RUNTIME.mkdir()
        clock = iter(range(0, 10_000, 100))
        with (
            patch.object(runtime.urllib.request, "urlopen", return_value=Response(archive())),
            patch.object(runtime.time, "monotonic", side_effect=lambda: next(clock)),
            self.assertRaises(ValueError),
        ):
            runtime.update(True, deadline=50)

    def test_interrupted_downloads_do_not_pile_up(self):
        runtime.RUNTIME.mkdir()
        stale = runtime.RUNTIME / ".soloist-leftover"
        stale.mkdir()
        (stale / "download.tar.gz").write_bytes(b"partial")
        stamp = int(time.time()) - 100
        with (
            patch.object(runtime.urllib.request, "urlopen", return_value=Response(archive())),
            patch.object(
                runtime, "run",
                return_value=subprocess.CompletedProcess([], 0, f"soloist build {stamp}", ""),
            ),
        ):
            runtime.update(True)
        self.assertFalse(stale.exists())

    def test_bad_build_metadata_is_treated_as_unknown(self):
        runtime.RUNTIME.mkdir()
        for body in ("[]", '"text"', '{"built_at": "soon"}', '{"built_at": null}'):
            (runtime.RUNTIME / "soloist-build.json").write_text(body)
            self.assertEqual(runtime.build_time(), 0)
        (runtime.RUNTIME / "soloist-build.json").write_text('{"built_at": 1234567890}')
        self.assertEqual(runtime.build_time(), 1234567890)

    def test_start_only_downloads_when_the_build_cannot_run(self):
        runtime.RUNTIME.mkdir()
        (runtime.RUNTIME / "soloist").write_bytes(b"old")
        now = int(time.time())
        cases = [
            (now - 10 * 86400, False, False),
            (now - 80 * 86400, False, True),
            (now - 91 * 86400, True, False),
        ]
        for built_at, downloads, renews_in_background in cases:
            (runtime.RUNTIME / "soloist-build.json").write_text(
                json.dumps({"built_at": built_at})
            )
            with (
                patch.object(runtime, "update") as update,
                patch.object(runtime, "run") as run,
            ):
                runtime.ensure_runnable_build()
            self.assertEqual(update.called, downloads)
            started = [
                call.args[0] for call in run.call_args_list
                if "--no-block" in call.args[0]
            ]
            self.assertEqual(bool(started), renews_in_background)

    def test_failed_renewal_keeps_a_build_that_still_works(self):
        runtime.RUNTIME.mkdir()
        (runtime.RUNTIME / "soloist").write_bytes(b"old")
        (runtime.RUNTIME / "soloist-build.json").write_text(
            json.dumps({"built_at": int(time.time()) - 89 * 86400})
        )
        with patch.object(runtime, "run", side_effect=OSError("no bus")):
            runtime.ensure_runnable_build()

    def test_clearing_a_key_notices_an_unreachable_keyring(self):
        outcomes = [
            (subprocess.CompletedProcess([], 0, "", ""), True),
            (subprocess.CompletedProcess([], 1, "", ""), True),
            (subprocess.CompletedProcess([], 1, "", "Error calling StartServiceByName"), False),
        ]
        for result, cleared in outcomes:
            with patch.object(runtime, "run", return_value=result):
                self.assertEqual(runtime.clear_key(), cleared)

    def test_empty_or_relative_xdg_paths_fall_back_to_home(self):
        for value in ("", "relative/path"):
            with patch.dict(runtime.os.environ, {"XDG_STATE_HOME": value}):
                self.assertEqual(
                    runtime.xdg_path("XDG_STATE_HOME", ".local/state"),
                    Path.home() / ".local/state",
                )
        with patch.dict(runtime.os.environ, {"XDG_STATE_HOME": "/custom/state"}):
            self.assertEqual(
                runtime.xdg_path("XDG_STATE_HOME", ".local/state"), Path("/custom/state")
            )

    def test_sync_refreshes_the_helper_and_units_without_touching_the_network(self):
        runtime.RUNTIME.mkdir()
        (runtime.RUNTIME / "soloist").write_bytes(b"old")
        (runtime.RUNTIME / "soloist-runtime.py").write_text("old helper")
        with (
            patch.object(runtime, "CONFIG", self.root / "config"),
            patch.object(runtime, "run",
                         return_value=subprocess.CompletedProcess([], 0, "", "")) as run,
            patch.object(runtime.urllib.request, "urlopen",
                         side_effect=AssertionError("sync must not download")),
        ):
            self.assertTrue(runtime.sync())
            helper = runtime.RUNTIME / "soloist-runtime.py"
            self.assertEqual(helper.read_bytes(), Path(runtime.__file__).read_bytes())
            self.assertTrue((self.root / "config/systemd/user" / runtime.UNIT).is_file())
            run.assert_any_call(["systemctl", "--user", "daemon-reload"])
            run.reset_mock()
            self.assertFalse(runtime.sync())
            run.assert_not_called()

    def test_sync_leaves_an_uninstalled_engine_alone(self):
        with (
            patch.object(runtime, "CONFIG", self.root / "config"),
            patch.object(runtime, "run") as run,
        ):
            self.assertFalse(runtime.sync())
        run.assert_not_called()
        self.assertFalse((self.root / "config").exists())

    def test_units_are_hardened_and_crash_dumps_cannot_expose_the_key(self):
        units = runtime.unit_files(self.root / "with space/backend", self.root / "conf")
        main = units[runtime.UNIT]
        self.assertIn(f'ExecStart="{self.root}/with space/backend" --soloist', main)
        for directive in (
            "LimitCORE=0", "LockPersonality=true", "RestrictSUIDSGID=true",
            "RestrictNamespaces=true", "SystemCallArchitectures=native",
        ):
            self.assertIn(directive, main)
        updater = units["omaspotify-soloist-update.service"]
        for directive in ("LimitCORE=0", "ProtectSystem=strict", "TimeoutStartSec=15min"):
            self.assertIn(directive, updater)

    def test_key_only_uses_stdin_and_not_status_output(self):
        secret = "fake-private-soloist-key"
        with (
            patch.object(runtime.sys, "argv", ["runtime", "save-key"]),
            patch.object(runtime.sys, "stdin", io.StringIO(secret)),
            patch.object(
                runtime, "run", return_value=subprocess.CompletedProcess([], 0, "", "")
            ) as run,
        ):
            runtime.main()
            args, kwargs = run.call_args
            self.assertNotIn(secret, str(args))
            self.assertEqual(kwargs["input"], secret)
        with (
            patch.object(runtime, "key", return_value=secret),
            patch.object(
                runtime, "run", return_value=subprocess.CompletedProcess([], 1, "", "")
            ),
        ):
            self.assertNotIn(secret, json.dumps(runtime.status()))


if __name__ == "__main__":
    unittest.main()
