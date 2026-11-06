"""Release orchestration tests: no Apple account, signing key or live server required."""

import contextlib
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

import release_ios as release


FIRST = "00008110-0000000000000001"
SECOND = "00008110-0000000000000002"


class FakeAPI:
    def __init__(self, config):
        self.rotations = 0
        self.uploads = []
        self.calls = []
        self.devices = [{"udid": FIRST, "name": "Server iPhone"}]

    def request(self, method, path, token):
        self.calls.append((method, path, token))
        if path.endswith("/session"):
            self.rotations += 1
            return {"access_token": f"access-{self.rotations}", "refresh_token": f"refresh-{self.rotations}"}
        return {"devices": self.devices}

    def upload(self, path, token):
        self.uploads.append((path.read_bytes(), token))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.signing = self.repo / "mobile/signing"
        self.signing.mkdir(parents=True)
        self.path = self.signing / "release.json"
        self.config = {
            "server_url": "https://example.test",
            "refresh_token": "initial-refresh",
            "team_id": "TEAM123456",
            "profile_name": "Private build",
            "bundle_id": "io.hrafnsyn.mobile",
        }
        self.path.write_text(json.dumps(self.config))
        self.api = FakeAPI(self.config)

    def run_release(self, build):
        with mock.patch.object(release.subprocess, "run", side_effect=build), contextlib.redirect_stdout(io.StringIO()):
            release.release(self.repo, self.path, api_factory=lambda _: self.api)

    def successful_build(self, command, **kwargs):
        self.assertFalse(kwargs.get("shell", False))
        self.assertNotIn("initial-refresh", command)
        if "--output-dir" in command:
            output = Path(command[command.index("--output-dir") + 1]) / "export"
            output.mkdir(parents=True)
            (output / "Hrafnsyn.ipa").write_bytes(b"new signed test IPA")
        return mock.Mock(returncode=0)

    def test_success_merges_devices_verifies_new_ipa_and_refreshes_after_build(self):
        local = self.signing / "devices.txt"
        original = f"{FIRST} Local name\n{SECOND} Local iPad\n"
        local.write_text(original)
        commands = []

        def build(command, **kwargs):
            commands.append(command)
            if "--devices-file" in command:
                devices = Path(command[command.index("--devices-file") + 1]).read_text()
                self.assertIn(FIRST + "\tLocal name", devices)
                self.assertIn(SECOND + "\tLocal iPad", devices)
                self.assertEqual(devices.count(FIRST), 1)
                self.assertEqual(json.loads(self.path.read_text())["refresh_token"], "refresh-1")
            if "--associated-domains-file" in command:
                domains = Path(command[command.index("--associated-domains-file") + 1])
                self.assertEqual(json.loads(domains.read_text()), ["example.test"])
            return self.successful_build(command, **kwargs)

        self.run_release(build)
        self.assertEqual(local.read_text(), original)
        self.assertEqual(len(commands), 3)
        self.assertTrue(commands[0][1].endswith("build-core.fish"))
        self.assertIn("verify", commands[2])
        self.assertEqual(self.api.uploads, [(b"new signed test IPA", "access-2")])
        self.assertEqual(json.loads(self.path.read_text())["refresh_token"], "refresh-2")
        self.assertEqual(self.api.calls[-1][-1], "refresh-1")
        self.assertEqual(list((self.repo / "mobile/build/releases").iterdir()), [])

    def test_build_failure_saves_rotation_but_never_uploads(self):
        def build(command, **kwargs):
            if command[1].endswith("export-adhoc.fish"):
                return mock.Mock(returncode=1)
            return self.successful_build(command, **kwargs)

        with self.assertRaisesRegex(release.ReleaseError, "export failed"):
            self.run_release(build)
        self.assertEqual(json.loads(self.path.read_text())["refresh_token"], "refresh-1")
        self.assertEqual(self.api.uploads, [])
        self.assertEqual(self.api.rotations, 1)

    def test_shared_core_failure_prevents_export_and_upload(self):
        with mock.patch.object(release.subprocess, "run", return_value=mock.Mock(returncode=1)) as build:
            with self.assertRaisesRegex(release.ReleaseError, "core build failed"), contextlib.redirect_stdout(io.StringIO()):
                release.release(self.repo, self.path, api_factory=lambda _: self.api)
        self.assertEqual(build.call_count, 1)
        self.assertTrue(build.call_args.args[0][1].endswith("build-core.fish"))
        self.assertEqual(self.api.uploads, [])

    def test_verification_failure_never_uploads(self):
        def build(command, **kwargs):
            if "verify" in command:
                return mock.Mock(returncode=1)
            return self.successful_build(command, **kwargs)

        with self.assertRaisesRegex(release.ReleaseError, "verification failed"):
            self.run_release(build)
        self.assertEqual(self.api.uploads, [])

    def test_stale_ipa_is_never_used_when_export_produces_nothing(self):
        stale = self.repo / "mobile/build/ad-hoc/export"
        stale.mkdir(parents=True)
        (stale / "old.ipa").write_bytes(b"stale IPA")
        with self.assertRaisesRegex(release.ReleaseError, "newly exported"):
            self.run_release(lambda *_args, **_kwargs: mock.Mock(returncode=0))
        self.assertEqual(self.api.uploads, [])

    def test_failed_device_lookup_keeps_the_rotated_refresh(self):
        original = self.api.request

        def request(method, path, token):
            if path.endswith("/devices"):
                raise release.ReleaseError("Device lookup failed")
            return original(method, path, token)

        self.api.request = request
        with self.assertRaisesRegex(release.ReleaseError, "Device lookup"):
            self.run_release(self.successful_build)
        self.assertEqual(json.loads(self.path.read_text())["refresh_token"], "refresh-1")

    def test_empty_devices_fail_before_build(self):
        self.api.devices = []
        with mock.patch.object(release.subprocess, "run") as build:
            with self.assertRaisesRegex(release.ReleaseError, "No collected or local"):
                release.release(self.repo, self.path, api_factory=lambda _: self.api)
            build.assert_not_called()

    def test_origin_rejects_credentials_redirect_targets_and_remote_http(self):
        for value in ("http://example.test", "https://user:secret@example.test", "https://example.test/path",
                      "https://example.test?token=secret", "https://example.test#fragment", "https://example.test\n"):
            with self.subTest(value=value), self.assertRaises(release.ReleaseError):
                release.validate_origin(value, True)
        release.validate_origin("http://127.0.0.1:4000", True)
        release.validate_origin("http://[::1]:4000", True)
        with self.assertRaises(release.ReleaseError):
            release.validate_origin("http://localhost:4000")

    def test_configuration_is_private_and_not_shell_source(self):
        self.config["profile_name"] = "$(touch should-not-exist)"
        self.path.write_text(json.dumps(self.config))
        loaded = release.load_config(self.path)
        self.assertEqual(loaded["profile_name"], "$(touch should-not-exist)")
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertFalse((self.repo / "should-not-exist").exists())
        self.assertFalse((self.repo / "mobile/signing/should-not-exist").exists())

    def test_associated_domains_default_to_https_instance_and_can_be_overridden(self):
        self.assertEqual(release.associated_domains(self.config), ["example.test"])
        self.assertEqual(release.associated_domains({**self.config, "associated_domains": []}), [])
        self.assertEqual(release.associated_domains({**self.config, "associated_domains": ["SHARE.example.test"]}), ["share.example.test"])
        for origin in ("https://127.0.0.1", "https://localhost", "https://example.test:8443", "http://127.0.0.1:4000"):
            self.assertEqual(release.associated_domains({**self.config, "server_url": origin, "allow_loopback_http": True}), [])

    def test_invalid_domains_fail_before_any_session_rotation(self):
        self.config["associated_domains"] = ["https://attacker.invalid/path"]
        self.path.write_text(json.dumps(self.config))
        with self.assertRaises(release.ReleaseError):
            self.run_release(self.successful_build)
        self.assertEqual(self.api.calls, [])

    def test_rotated_token_is_atomic_private_and_preserves_other_settings(self):
        release.save_rotated_token(self.path, self.config, "next-refresh")
        loaded = json.loads(self.path.read_text())
        self.assertEqual(loaded, {**self.config, "refresh_token": "next-refresh"})
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(list(self.signing.glob(".release-*")), [])

    def test_lock_prevents_concurrent_refresh(self):
        with release.release_lock(self.path):
            with self.assertRaisesRegex(release.ReleaseError, "Another release"):
                with release.release_lock(self.path):
                    self.fail("Second lock acquired")

    def test_device_names_are_safe_and_server_ids_are_validated(self):
        devices = release.collected_devices({"devices": [{"udid": FIRST.lower(), "name": "A\nB" + "x" * 80}]})
        self.assertEqual(len(devices[FIRST]), 50)
        self.assertNotIn("\n", devices[FIRST])
        with self.assertRaises(release.ReleaseError):
            release.collected_devices({"devices": [{"udid": "invalid", "name": "Bad"}]})

    def test_apple_configuration_maps_only_known_environment_keys(self):
        config = {**self.config, "sync_devices": True, "apple": {
            "key_id": "KEY", "issuer_id": "ISSUER", "key_path": "private.p8", "certificate_id": "CERT"
        }}
        environment = release.signing_environment(config, self.path)
        self.assertEqual(environment["HRAFNSYN_ASC_KEY_PATH"], str((self.signing / "private.p8").resolve()))
        self.assertEqual(environment["HRAFNSYN_ASC_KEY_ID"], "KEY")
        with self.assertRaises(release.ReleaseError):
            release.signing_environment({**config, "apple": {"PATH": "bad"}}, self.path)


class TransportTests(unittest.TestCase):
    def api(self):
        return release.ReleaseAPI({"server_url": "https://example.test"})

    def test_redirect_is_not_followed_and_error_does_not_include_credentials(self):
        connection = mock.Mock()
        connection.getresponse.return_value = mock.Mock(status=302)
        api = self.api()
        with mock.patch.object(api, "connection", return_value=connection):
            with self.assertRaisesRegex(release.ReleaseError, "not forwarded") as error:
                api.request("POST", "/api/mobile-release/session", "private-refresh-token")
        self.assertNotIn("private-refresh-token", str(error.exception))
        self.assertEqual(connection.request.call_count, 1)
        connection.close.assert_called_once()

    def test_upload_streams_bounded_chunks_with_correct_multipart_length(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "new.ipa"
            data = b"x" * (2 * 1024 * 1024 + 7)
            path.write_bytes(data)
            connection = mock.Mock()
            response = mock.Mock(status=201)
            response.read.return_value = b'{"status":"published"}'
            connection.getresponse.return_value = response
            api = self.api()
            with mock.patch.object(api, "connection", return_value=connection), mock.patch.object(Path, "read_bytes", side_effect=AssertionError("Whole file read")):
                api.upload(path, "access-token")
            chunks = [call.args[0] for call in connection.send.call_args_list]
            self.assertEqual(b"".join(chunks[1:-1]), data)
            self.assertLessEqual(max(map(len, chunks)), 1024 * 1024)
            headers = dict(call.args for call in connection.putheader.call_args_list)
            self.assertEqual(int(headers["Content-Length"]), sum(map(len, chunks)))
            self.assertIn(b'name="ipa"; filename="Hrafnsyn.ipa"', chunks[0])
            connection.close.assert_called_once()

    def test_error_body_is_never_reflected_to_terminal(self):
        connection = mock.Mock()
        connection.getresponse.return_value = mock.Mock(status=403)
        api = self.api()
        with mock.patch.object(api, "connection", return_value=connection):
            with self.assertRaisesRegex(release.ReleaseError, "HTTP 403"):
                api.request("GET", "/api/mobile-release/devices", "secret")
        connection.getresponse.return_value.read.assert_not_called()


if __name__ == "__main__":
    unittest.main()
