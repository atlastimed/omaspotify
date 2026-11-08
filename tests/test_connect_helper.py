#!/usr/bin/env python3
"""Focused tests for Spotify Connect receiver authorization."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse
from pathlib import Path
from unittest import mock

SOURCE_ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = SOURCE_ROOT / "scripts" / "spotify-connect-device.py"
SPEC = importlib.util.spec_from_file_location("spotify_connect_device", HELPER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Spotify Connect helper")
helper = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = helper
SPEC.loader.exec_module(helper)


class FakeResponse:
    def __init__(self, payload: dict[str, str], status: int = 200) -> None:
        self.payload = json.dumps(payload).encode("utf-8")
        self.status = status

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self, _limit: int) -> bytes:
        return self.payload


class ConnectHelperTests(unittest.TestCase):
    def test_avahi_escapes_are_utf8_bytes_and_dots(self) -> None:
        self.assertEqual(helper.avahi_unescape(r"K\195\188che"), "K\u00fcche")
        self.assertEqual(helper.avahi_unescape(r"Living\032Room\.1"), "Living Room.1")

    def test_receiver_paths_cannot_carry_a_query_or_escape(self) -> None:
        for bad in ("/cgi-bin/reboot.cgi?now=1", "/a#b", "/a%2f", "/../etc", "zc", "/a b"):
            with self.assertRaises(helper.ConnectError, msg=bad):
                helper.endpoint_path(bad)
        self.assertEqual(helper.endpoint_path("/zc/0"), "/zc/0")
        self.assertEqual(helper.endpoint_path(""), "/")

    def test_cloud_metadata_address_is_not_a_receiver(self) -> None:
        with self.assertRaises(helper.ConnectError):
            helper.safe_address("169.254.169.254")
        self.assertEqual(helper.safe_address("169.254.10.20"), "169.254.10.20")

    def test_discovery_probes_each_receiver_once(self) -> None:
        browse = "\n".join(
            f'=;eth0;IPv4;Speaker;_spotify-connect._tcp;local;speaker.local;192.168.1.9;5353;"CPath=/zc"{suffix}'
            for suffix in ("", "", " ")
        )
        calls: list[str] = []

        def fake_request_json(address: str, port: int, path: str, *_rest: object) -> dict[str, object]:
            calls.append(f"{address}:{port}{path}")
            return {"status": 101, "deviceID": "0123456789abcdef", "remoteName": "Speaker"}

        with mock.patch.object(helper, "browse_spotify_connect", return_value=browse), \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json):
            devices = helper.discover_receivers()

        self.assertEqual(len(calls), 1)
        self.assertEqual([item["name"] for item in devices], ["Speaker"])

    def test_a_silent_receiver_does_not_hold_up_the_others(self) -> None:
        browse = "\n".join([
            '=;eth0;IPv4;Slow;_spotify-connect._tcp;local;a.local;192.168.1.8;5353;"CPath=/zc"',
            '=;eth0;IPv4;Fast;_spotify-connect._tcp;local;b.local;192.168.1.9;5353;"CPath=/zc"',
        ])
        release = threading.Event()
        self.addCleanup(release.set)

        def fake_request_json(address: str, *_rest: object) -> dict[str, object]:
            if address.endswith(".8"):
                release.wait(30)
            return {"status": 101, "deviceID": "fedcba9876543210", "remoteName": "Fast"}

        started = time.monotonic()
        with mock.patch.object(helper, "browse_spotify_connect", return_value=browse), \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json), \
                mock.patch.object(helper, "PROBE_DEADLINE_SECONDS", 0.5):
            devices = helper.discover_receivers()

        self.assertLess(time.monotonic() - started, 5)
        self.assertEqual([item["name"] for item in devices], ["Fast"])

    def test_token_receiver_needs_no_saved_credential(self) -> None:
        receiver = {
            "id": "0123456789abcdef0123456789abcdef01234567",
            "address": "192.168.1.20",
            "port": 5389,
            "cpath": "/zc",
            "serviceVersion": "1.0",
            "brand": "JBL",
            "tokenType": "accesstoken",
            "clientId": "76642c7bcc9c466bb99a44ce206edbbe",
        }
        posted: list[dict[str, str]] = []

        def fake_request_json(
            _address: str, _port: int, _path: str,
            method: str = "GET", fields: dict[str, str] | None = None,
        ) -> dict[str, object]:
            if method == "GET":
                return {"status": 101, "deviceID": receiver["id"], "tokenType": "accesstoken"}
            posted.append(dict(fields or {}))
            return {"status": 101}

        token = "desktop-streaming-token-value-1234567890"
        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(helper, "load_credentials",
                                  side_effect=helper.ConnectError("no saved credential")), \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json):
            result = helper.activate_receiver(receiver["id"], token, "harry")

        self.assertEqual(result["status"], "activated")
        self.assertEqual(posted[0]["blob"], token)
        self.assertEqual(posted[0]["userName"], "harry")

    def test_the_deadline_cannot_be_retried_away(self) -> None:
        self.assertFalse(issubclass(helper.DeadlineExceeded, Exception))
        calls: list[int] = []

        def slow(*_args: object) -> dict[str, object]:
            calls.append(1)
            helper.on_deadline(0, None)
            return {}

        with mock.patch.object(helper, "request_json", side_effect=slow), \
                mock.patch.object(helper.time, "sleep"), \
                self.assertRaises(helper.DeadlineExceeded):
            helper.request_json_with_retry("192.168.1.2", 1000, "/zc")
        self.assertEqual(len(calls), 1)

    def test_a_token_is_sent_under_the_signed_in_account(self) -> None:
        receiver = {
            "id": "0123456789abcdef0123456789abcdef01234567",
            "address": "192.168.1.20",
            "port": 5389,
            "cpath": "/zc",
            "serviceVersion": "1.0",
            "tokenType": "accesstoken",
        }
        posted: list[dict[str, str]] = []

        def fake_request_json(
            _address: str, _port: int, _path: str,
            method: str = "GET", fields: dict[str, str] | None = None,
        ) -> dict[str, object]:
            if method == "GET":
                return {"status": 101, "deviceID": receiver["id"], "tokenType": "accesstoken"}
            posted.append(dict(fields or {}))
            return {"status": 101}

        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(helper, "load_credentials",
                                  return_value=("old-account", 1, b"stored")), \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json):
            helper.activate_receiver(receiver["id"],
                                     "desktop-streaming-token-value-1234567890", "current")
        self.assertEqual(posted[0]["userName"], "current")

    def test_device_auth_never_follows_a_redirect_with_the_token(self) -> None:
        handler = helper.NoRedirect()
        request = helper.urllib.request.Request("https://spclient.wg.spotify.com/x")
        self.assertIsNone(handler.redirect_request(
            request, None, 302, "Found", {}, "https://elsewhere.invalid/"))

    def test_credentials_prefer_durable_state_and_keep_cache_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            root = Path(raw_root)
            with mock.patch.dict(os.environ, {
                "XDG_STATE_HOME": str(root / "state"),
                "XDG_CACHE_HOME": str(root / "cache"),
            }):
                paths = helper.credentials_paths()

        self.assertEqual(paths, [
            root / "state/omaspotify/oauth/credentials.json",
            root / "state/omaspotify/zeroconf/credentials.json",
            root / "cache/spotifyd/oauth/credentials.json",
            root / "cache/spotifyd/zeroconf/credentials.json",
        ])

    def test_access_token_exchange_uses_receiver_identity(self) -> None:
        captured: list[object] = []

        def fake_urlopen(request: object, timeout: int) -> FakeResponse:
            captured.extend([request, timeout])
            return FakeResponse({"accessToken": "receiver-access-token-value-1234567890"})

        desktop_token = "desktop-access-token-value-1234567890"
        receiver = {
            "id": "0123456789abcdef0123456789abcdef01234567",
            "clientId": "76642c7bcc9c466bb99a44ce206edbbe",
        }
        with mock.patch.object(helper.NO_REDIRECT_OPENER, "open", side_effect=fake_urlopen):
            result = helper.exchange_access_token(desktop_token, receiver)

        self.assertEqual(result, "receiver-access-token-value-1234567890")
        request = captured[0]
        fields = json.loads(request.data.decode("utf-8"))
        self.assertEqual(fields, {
            "clientId": receiver["clientId"],
            "deviceId": receiver["id"],
        })
        self.assertEqual(request.get_header("Authorization"), f"Bearer {desktop_token}")
        self.assertNotIn(desktop_token, request.full_url)
        self.assertEqual(captured[1], 10)

    def test_sonos_token_exchange_uses_receiver_audience(self) -> None:
        captured: list[object] = []

        def fake_urlopen(request: object, timeout: int) -> FakeResponse:
            captured.extend([request, timeout])
            return FakeResponse({"access_token": "receiver-code-value-1234567890"})

        desktop_token = "desktop-access-token-value-1234567890"
        with mock.patch.object(helper.urllib.request, "urlopen", side_effect=fake_urlopen):
            result = helper.exchange_authorization_code(desktop_token, {
                "brand": "Sonos",
                "clientId": "ignored-for-sonos",
            })

        self.assertEqual(result, "receiver-code-value-1234567890")
        request = captured[0]
        fields = urllib.parse.parse_qs(request.data.decode("utf-8"))
        self.assertEqual(fields["audience"], [helper.SONOS_CLIENT_ID])
        self.assertEqual(fields["client_id"], [helper.SPOTIFY_DESKTOP_CLIENT_ID])
        self.assertEqual(fields["scope"], ["streaming"])
        self.assertEqual(fields["subject_token"], [desktop_token])
        self.assertNotIn(desktop_token, request.full_url)
        self.assertEqual(captured[1], 10)

    def test_invalid_exchange_token_is_rejected_before_network(self) -> None:
        with mock.patch.object(helper.urllib.request, "urlopen") as urlopen:
            with self.assertRaises(helper.ConnectError):
                helper.exchange_authorization_code("too short", {
                    "brand": "Sonos",
                    "clientId": helper.SONOS_CLIENT_ID,
                })
        urlopen.assert_not_called()

    def test_authorization_code_receiver_uses_unencrypted_blob(self) -> None:
        receiver = {
            "id": "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d",
            "address": "192.168.1.10",
            "port": 1400,
            "cpath": "/zc",
            "serviceVersion": "2.9.0",
            "brand": "Sonos",
            "tokenType": "authorization_code",
            "clientId": helper.SONOS_CLIENT_ID,
        }
        posted: dict[str, str] = {}

        def fake_request_json(
            _address: str,
            _port: int,
            _path: str,
            method: str = "GET",
            fields: dict[str, str] | None = None,
        ) -> dict[str, object]:
            if method == "GET":
                return {
                    "status": 101,
                    "deviceID": receiver["id"],
                    "tokenType": "authorization_code",
                }
            posted.update(fields or {})
            return {"status": 101}

        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(
                    helper, "load_credentials",
                    return_value=("canonical-user", 1, b"stored-credential"),
                ), \
                mock.patch.object(
                    helper, "exchange_authorization_code",
                    return_value="receiver-code-value-1234567890",
                ) as exchange, \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json):
            result = helper.activate_receiver(receiver["id"], "desktop-token")

        self.assertEqual(result, {"id": receiver["id"], "status": "activated"})
        exchange.assert_called_once_with("desktop-token", receiver)
        self.assertEqual(posted["tokenType"], "authorization_code")
        self.assertEqual(posted["clientKey"], "")
        self.assertEqual(posted["blob"], "receiver-code-value-1234567890")
        self.assertEqual(posted["loginId"], "canonical-user")
        self.assertEqual(posted["userName"], "canonical-user")

    def test_access_token_receiver_uses_streaming_token_directly(self) -> None:
        receiver = {
            "id": "0123456789abcdef0123456789abcdef01234567",
            "address": "192.168.1.20",
            "port": 5389,
            "cpath": "/zc",
            "serviceVersion": "1.0",
            "brand": "JBL",
            "tokenType": "accesstoken",
            "clientId": "76642c7bcc9c466bb99a44ce206edbbe",
        }
        posted: dict[str, str] = {}

        def fake_request_json(
            _address: str,
            _port: int,
            _path: str,
            method: str = "GET",
            fields: dict[str, str] | None = None,
        ) -> dict[str, object]:
            if method == "GET":
                return {
                    "status": 101,
                    "deviceID": receiver["id"],
                    "tokenType": "accesstoken",
                }
            posted.update(fields or {})
            return {"status": 101}

        streaming_token = "desktop-streaming-token-value-1234567890"
        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(
                    helper, "load_credentials",
                    return_value=("canonical-user", 1, b"stored-credential"),
                ), \
                mock.patch.object(helper, "exchange_access_token") as exchange, \
                mock.patch.object(helper, "build_login_blob") as build_blob, \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json):
            result = helper.activate_receiver(receiver["id"], streaming_token)

        self.assertEqual(result, {"id": receiver["id"], "status": "activated"})
        exchange.assert_not_called()
        build_blob.assert_not_called()
        self.assertEqual(posted["tokenType"], "accesstoken")
        self.assertEqual(posted["clientKey"], "")
        self.assertEqual(posted["blob"], streaming_token)
        self.assertEqual(posted["loginId"], "canonical-user")
        self.assertEqual(posted["userName"], "canonical-user")

    def test_access_token_receiver_mints_token_after_login_failure(self) -> None:
        receiver = {
            "id": "0123456789abcdef0123456789abcdef01234567",
            "address": "192.168.1.20",
            "port": 5389,
            "cpath": "/zc",
            "serviceVersion": "1.0",
            "brand": "JBL",
            "tokenType": "accesstoken",
            "clientId": "76642c7bcc9c466bb99a44ce206edbbe",
        }
        posted: list[dict[str, str]] = []

        def fake_request_json(
            _address: str,
            _port: int,
            _path: str,
            method: str = "GET",
            fields: dict[str, str] | None = None,
        ) -> dict[str, object]:
            if method == "GET":
                return {
                    "status": 101,
                    "deviceID": receiver["id"],
                    "tokenType": "accesstoken",
                }
            posted.append(dict(fields or {}))
            if len(posted) == 1:
                return {"status": 202, "statusString": "ERROR-LOGIN-FAILED"}
            return {"status": 101}

        streaming_token = "desktop-streaming-token-value-1234567890"
        receiver_token = "receiver-access-token-value-1234567890"
        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(
                    helper, "load_credentials",
                    return_value=("canonical-user", 1, b"stored-credential"),
                ), \
                mock.patch.object(
                    helper, "exchange_access_token", return_value=receiver_token,
                ) as exchange, \
                mock.patch.object(helper, "build_login_blob") as build_blob, \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json), \
                mock.patch.object(helper.time, "sleep"):
            result = helper.activate_receiver(receiver["id"], streaming_token)

        self.assertEqual(result, {"id": receiver["id"], "status": "activated"})
        exchange.assert_called_once_with(streaming_token, receiver)
        build_blob.assert_not_called()
        self.assertEqual([item["blob"] for item in posted], [streaming_token, receiver_token])
        self.assertEqual(posted[1]["tokenType"], "accesstoken")

    def test_access_token_receiver_falls_back_when_device_auth_fails(self) -> None:
        receiver = {
            "id": "0123456789abcdef0123456789abcdef01234567",
            "address": "192.168.1.20",
            "port": 5389,
            "cpath": "/zc",
            "serviceVersion": "1.0",
            "brand": "JBL",
            "tokenType": "accesstoken",
            "clientId": "76642c7bcc9c466bb99a44ce206edbbe",
            "publicKey": "QQ==",
        }
        posted: list[dict[str, str]] = []

        def fake_request_json(
            _address: str,
            _port: int,
            _path: str,
            method: str = "GET",
            fields: dict[str, str] | None = None,
        ) -> dict[str, object]:
            if method == "GET":
                return {
                    "status": 101,
                    "deviceID": receiver["id"],
                    "tokenType": "accesstoken",
                    "publicKey": receiver["publicKey"],
                }
            posted.append(dict(fields or {}))
            if len(posted) == 1:
                return {"status": 202, "statusString": "ERROR-LOGIN-FAILED"}
            return {"status": 101}

        streaming_token = "desktop-streaming-token-value-1234567890"
        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(
                    helper, "load_credentials",
                    return_value=("canonical-user", 1, b"stored-credential"),
                ), \
                mock.patch.object(
                    helper, "exchange_access_token",
                    side_effect=helper.ConnectError("invalid response"),
                ) as exchange, \
                mock.patch.object(
                    helper, "build_login_blob",
                    return_value=("encrypted-blob", "client-key"),
                ) as build_blob, \
                mock.patch.object(helper, "request_json", side_effect=fake_request_json), \
                mock.patch.object(helper.time, "sleep"):
            result = helper.activate_receiver(receiver["id"], streaming_token)

        self.assertEqual(result, {"id": receiver["id"], "status": "activated"})
        exchange.assert_called_once_with(streaming_token, receiver)
        build_blob.assert_called_once()
        self.assertEqual(posted[0]["blob"], streaming_token)
        self.assertEqual(posted[1]["tokenType"], "default")
        self.assertEqual(posted[1]["blob"], "encrypted-blob")
        self.assertEqual(posted[1]["clientKey"], "client-key")

    def test_access_token_receiver_rejects_missing_streaming_token(self) -> None:
        receiver = {
            "id": "0123456789abcdef0123456789abcdef01234567",
            "address": "192.168.1.20",
            "port": 5389,
            "cpath": "/zc",
            "serviceVersion": "1.0",
            "tokenType": "accesstoken",
            "clientId": "76642c7bcc9c466bb99a44ce206edbbe",
        }

        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(
                    helper, "load_credentials",
                    return_value=("canonical-user", 1, b"stored-credential"),
                ), \
                mock.patch.object(helper, "request_json", return_value={
                    "status": 101,
                    "deviceID": receiver["id"],
                    "tokenType": "accesstoken",
                }) as request:
            with self.assertRaises(helper.ConnectError):
                helper.activate_receiver(receiver["id"], "")

        self.assertEqual(request.call_count, 1)

    def test_sonos_local_volume_control_uses_rendering_service(self) -> None:
        receiver = {
            "id": "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d",
            "address": "192.168.1.10",
            "port": 1400,
            "brand": "Sonos",
        }
        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(helper, "request_sonos_soap") as soap:
            result = helper.control_receiver(receiver["id"], "volume", "37")

        self.assertEqual(result["status"], "controlled")
        soap.assert_called_once_with(
            receiver,
            helper.SONOS_RENDERING_CONTROL,
            "/MediaRenderer/RenderingControl/Control",
            "SetVolume",
            {"InstanceID": "0", "Channel": "Master", "DesiredVolume": "37"},
        )

    def test_sonos_control_uses_discovery_cache_instead_of_avahi(self) -> None:
        receiver = {
            "id": "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d",
            "address": "192.168.1.10",
            "port": 1400,
            "cpath": "/",
            "brand": "Sonos",
            "serviceVersion": "1.0",
        }
        with tempfile.TemporaryDirectory() as raw_runtime:
            runtime_dir = Path(raw_runtime)
            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime_dir)}):
                helper.write_receiver_cache([receiver])
                with mock.patch.object(helper, "discover_receivers") as discover, \
                        mock.patch.object(helper, "request_sonos_soap") as soap:
                    result = helper.control_receiver(receiver["id"], "pause")

        self.assertEqual(result["status"], "controlled")
        discover.assert_not_called()
        self.assertEqual(soap.call_args.args[0]["address"], "192.168.1.10")

    def test_sonos_volume_reads_rendering_service_value(self) -> None:
        receiver = {
            "id": "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d",
            "address": "192.168.1.10",
            "port": 1400,
            "brand": "Sonos",
        }
        response = helper.ElementTree.fromstring(
            "<Envelope><Body><GetVolumeResponse>"
            "<CurrentVolume>42</CurrentVolume>"
            "</GetVolumeResponse></Body></Envelope>"
        )
        with mock.patch.object(
            helper, "request_sonos_soap", return_value=response
        ) as soap:
            result = helper.sonos_volume(receiver)

        self.assertEqual(result, 42)
        soap.assert_called_once_with(
            receiver,
            helper.SONOS_RENDERING_CONTROL,
            "/MediaRenderer/RenderingControl/Control",
            "GetVolume",
            {"InstanceID": "0", "Channel": "Master"},
        )

    def test_sonos_seek_formats_relative_time(self) -> None:
        receiver = {
            "id": "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d",
            "address": "192.168.1.10",
            "port": 1400,
            "brand": "Sonos",
        }
        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(helper, "request_sonos_soap") as soap:
            helper.control_receiver(receiver["id"], "seek", "3723")

        self.assertEqual(
            soap.call_args.args[4],
            {"InstanceID": "0", "Unit": "REL_TIME", "Target": "01:02:03"},
        )

    def test_sonos_accepts_shuffle_with_repeat_one(self) -> None:
        receiver = {
            "id": "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d",
            "address": "192.168.1.10",
            "port": 1400,
            "brand": "Sonos",
        }
        with mock.patch.object(helper, "discover_receivers", return_value=[receiver]), \
                mock.patch.object(helper, "request_sonos_soap") as soap:
            helper.control_receiver(receiver["id"], "mode", "SHUFFLE_REPEAT_ONE")

        self.assertEqual(soap.call_args.args[3], "SetPlayMode")
        self.assertEqual(
            soap.call_args.args[4],
            {"InstanceID": "0", "NewPlayMode": "SHUFFLE_REPEAT_ONE"},
        )

    def test_receiver_request_retries_transient_sleep(self) -> None:
        with mock.patch.object(
            helper,
            "request_json",
            side_effect=[helper.ConnectError("receiver did not respond"), {"status": 101}],
        ) as request, mock.patch.object(helper.time, "sleep") as sleep:
            result = helper.request_json_with_retry(
                "192.168.1.10", 1400, "/zc", attempts=3
            )

        self.assertEqual(result, {"status": 101})
        self.assertEqual(request.call_count, 2)
        sleep.assert_called_once_with(0.4)

    def test_browse_spotify_connect_keeps_stdout_when_avahi_times_out(self) -> None:
        dump = '=;wlp0s20f3;IPv4;office;_spotify-connect._tcp;local;host.local;192.168.1.10;1400;""\n'
        with mock.patch.object(
            helper.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired(
                cmd=["avahi-browse"], timeout=8, output=dump.encode("utf-8")
            ),
        ):
            self.assertEqual(helper.browse_spotify_connect(), dump)

    def test_real_timeout_keeps_partial_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "avahi-browse"
            executable.write_text(
                "#!/usr/bin/env python3\nimport time\n"
                "print('resolved receiver', flush=True)\ntime.sleep(2)\n"
            )
            executable.chmod(0o755)
            with mock.patch.dict(os.environ, {"PATH": directory + os.pathsep + os.environ["PATH"]}), \
                 mock.patch.object(helper, "AVAHI_BROWSE_TIMEOUT_SECONDS", 0.15):
                self.assertEqual(helper.browse_spotify_connect(), "resolved receiver\n")

    def test_browse_spotify_connect_fails_when_timeout_has_no_stdout(self) -> None:
        with mock.patch.object(
            helper.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired(
                cmd=["avahi-browse"], timeout=8, output=""
            ),
        ):
            with self.assertRaises(helper.ConnectError):
                helper.browse_spotify_connect()

    def test_discover_receivers_accepts_ipv4_address_on_ipv6_labeled_record(self) -> None:
        dump = (
            "=;wlp0s20f3;IPv6;sonosRINCON_OFFICE;_spotify-connect._tcp;local;"
            "Sonos-Office.local;192.168.1.10;1400;\"CPath=/spotifyzc\" \"VERSION=1\"\n"
        )
        info = {
            "status": 101,
            "deviceID": "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d",
            "remoteName": "Office",
            "deviceType": "SPEAKER",
            "brandDisplayName": "Sonos",
            "modelDisplayName": "Bookshelf",
            "tokenType": "authorization_code",
            "clientID": "9b377073ea334637b1406f329ce005de",
            "publicKey": "abc",
        }
        with mock.patch.object(helper, "browse_spotify_connect", return_value=dump), \
                mock.patch.object(helper, "request_json", return_value=info) as request:
            devices = helper.discover_receivers()

        self.assertEqual(len(devices), 1)
        self.assertEqual(devices[0]["id"], info["deviceID"])
        self.assertEqual(devices[0]["address"], "192.168.1.10")
        self.assertEqual(devices[0]["name"], "Office")
        request.assert_called_once()
        self.assertEqual(request.call_args.args[0], "192.168.1.10")
        self.assertEqual(request.call_args.args[1], 1400)

    def test_discover_receivers_skips_true_ipv6_addresses(self) -> None:
        dump = (
            "=;wlp0s20f3;IPv6;sonosRINCON_OFFICE;_spotify-connect._tcp;local;"
            "Sonos-Office.local;fd12:3456:789a::10;1400;\"CPath=/spotifyzc\" \"VERSION=1\"\n"
        )
        with mock.patch.object(helper, "browse_spotify_connect", return_value=dump), \
                mock.patch.object(helper, "request_json") as request:
            devices = helper.discover_receivers()

        self.assertEqual(devices, [])
        request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
