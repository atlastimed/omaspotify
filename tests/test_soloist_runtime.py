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
