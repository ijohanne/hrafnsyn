"""Run with nix develop -c python3 -m unittest discover -s mobile/scripts -p 'test_ios_devices.py'."""

import base64
import datetime as dt
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import ios_devices as signing


UDID = "00008110-0000000000000001"
SECOND = "00008110-0000000000000002"
TEAM = "TESTTEAM01"
BUNDLE = "io.example.fixture"


def profile():
    return {
        "Name": "Test Ad Hoc",
        "UUID": "00000000-0000-4000-8000-000000000001",
        "ExpirationDate": dt.datetime.now() + dt.timedelta(days=30),
        "TeamIdentifier": [TEAM],
        "ApplicationIdentifierPrefix": [TEAM],
        "Entitlements": {"application-identifier": f"{TEAM}.{BUNDLE}", "get-task-allow": False},
        "ProvisionedDevices": [UDID],
        "DeveloperCertificates": [b"fixture certificate"],
    }


class FakeAPI:
    def __init__(self, existing=True, status="ENABLED", profiles=None, platform="IOS", capabilities=None):
        self.existing = existing
        self.status = status
        self.profiles = profiles or []
        self.posts = []
        self.platform = platform
        self.capabilities = capabilities or []

    def list(self, resource, **filters):
        if resource == "bundleIds":
            return [{"id": "bundle", "attributes": {"identifier": BUNDLE, "platform": self.platform}}]
        if resource == "devices":
            if self.existing:
                return [{"id": "device", "attributes": {"udid": UDID, "status": self.status}}]
            return []
        if resource == "profiles":
            return self.profiles
        if resource == "bundleIds/bundle/bundleIdCapabilities":
            return self.capabilities
        raise AssertionError(resource)

    def request(self, method, path, body=None):
        self.posts.append((method, path, body))
        if path == "/v1/devices":
            return {"data": {"id": "new-device", "attributes": {**body["data"]["attributes"], "status": self.status}}}
        if path == "/v1/profiles":
            return {"data": {"attributes": {"profileContent": base64.b64encode(b"fixture CMS").decode()}}}
        if path == "/v1/bundleIdCapabilities":
            return {"data": body["data"]}
        raise AssertionError(path)


class DeviceListTests(unittest.TestCase):
    def test_comments_normalization_and_private_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "devices.txt"
            path.write_text(f"# ignored\n\n{UDID.lower()} Test phone\n")
            self.assertEqual(signing.read_devices(path), {UDID: "Test phone"})
            path.write_text(f"{UDID} One\n{UDID} Two\n")
            with self.assertRaises(signing.SigningError) as error:
                signing.read_devices(path)
            self.assertIn("line 2", str(error.exception))
            self.assertNotIn(UDID, str(error.exception))

    def test_empty_or_malformed_file_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "devices.txt"
            for content in ["", "bad-device My phone", f"{UDID} " + "x" * 51]:
                path.write_text(content)
                with self.subTest(content=content):
                    with self.assertRaises(signing.SigningError):
                        signing.read_devices(path)

    def test_profile_requires_every_requested_device(self):
        with self.assertRaises(signing.SigningError) as error:
            signing.validate_profile(profile(), {UDID: "one", SECOND: "two"}, TEAM, BUNDLE)
        self.assertIn("missing 1 device", str(error.exception))
        self.assertNotIn(SECOND, str(error.exception))

    def test_wrong_team_bundle_expired_development_or_wrong_certificate_rejected(self):
        cases = [
            {"TeamIdentifier": ["OTHER"]},
            {"ExpirationDate": dt.datetime.now() - dt.timedelta(days=1)},
            {"Entitlements": {"application-identifier": f"{TEAM}.other", "get-task-allow": False}},
            {"Entitlements": {"application-identifier": f"{TEAM}.{BUNDLE}", "get-task-allow": True}},
            {"ProvisionsAllDevices": True},
            {"DeveloperCertificates": []},
        ]
        for update in cases:
            candidate = {**profile(), **update}
            with self.subTest(update=update):
                with self.assertRaises(signing.SigningError):
                    signing.validate_profile(candidate, {UDID: "phone"}, TEAM, BUNDLE)

    def test_valid_profile_and_exact_managed_device_set(self):
        candidate = profile()
        signing.validate_profile(candidate, {UDID: "phone"}, TEAM, BUNDLE, b"fixture certificate", exact=True)
        candidate["ProvisionedDevices"].append(SECOND)
        with self.assertRaises(signing.SigningError):
            signing.validate_profile(candidate, {UDID: "phone"}, TEAM, BUNDLE, exact=True)

    def test_ipa_profile_checked_and_absence_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = Path(tmp) / "test.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/App.app/embedded.mobileprovision", b"CMS")
            with patch.object(signing, "inspect_content", return_value=profile()) as inspect, \
                    patch.object(signing, "verify_signed_app"):
                signing.verify_ipa(ipa, {UDID: "phone"}, TEAM, BUNDLE, tmp)
                inspect.assert_called_once_with(b"CMS", tmp)
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/App.app/Info.plist", b"info")
            with self.assertRaises(signing.SigningError):
                signing.verify_ipa(ipa, {UDID: "phone"}, TEAM, BUNDLE, tmp)


class SyncTests(unittest.TestCase):
    def sync(self, api):
        with patch.object(signing, "certificate_for_team", return_value=b"fixture certificate"), \
                patch.object(signing, "inspect_content", return_value=profile()):
            return signing.sync_profile(api, {UDID: "Fixture phone"}, TEAM, BUNDLE, "Hrafnsyn", "certificate", ".")

    def test_new_device_registered_and_used_in_adhoc_relationships(self):
        api = FakeAPI(existing=False)
        content, returned = self.sync(api)
        self.assertEqual(content, b"fixture CMS")
        self.assertEqual(returned["UUID"], profile()["UUID"])
        self.assertEqual([post[1] for post in api.posts], ["/v1/devices", "/v1/profiles"])
        device = api.posts[0][2]["data"]["attributes"]
        self.assertEqual(device, {"udid": UDID, "name": "Fixture phone", "platform": "IOS"})
        body = api.posts[1][2]["data"]
        self.assertEqual(body["attributes"]["profileType"], "IOS_APP_ADHOC")
        self.assertEqual(body["relationships"]["devices"]["data"], [{"type": "devices", "id": "new-device"}])
        self.assertEqual(body["relationships"]["certificates"]["data"], [{"type": "certificates", "id": "certificate"}])

    def test_existing_device_is_not_registered_again(self):
        api = FakeAPI()
        self.sync(api)
        self.assertEqual([post[1] for post in api.posts], ["/v1/profiles"])

    def test_universal_bundle_can_create_an_ios_adhoc_profile(self):
        api = FakeAPI(platform="UNIVERSAL")
        self.sync(api)
        self.assertEqual(api.posts[0][2]["data"]["attributes"]["profileType"], "IOS_APP_ADHOC")

    def test_mac_only_bundle_cannot_register_devices_or_create_profile(self):
        api = FakeAPI(existing=False, platform="MAC_OS")
        with self.assertRaises(signing.SigningError):
            self.sync(api)
        self.assertEqual(api.posts, [])

    def test_disabled_or_pending_devices_never_get_a_profile(self):
        for status in ["DISABLED", "PROCESSING"]:
            api = FakeAPI(status=status)
            with self.assertRaises(signing.SigningError):
                self.sync(api)
            self.assertEqual(api.posts, [])

    def test_new_processing_device_is_read_back_before_provisioning(self):
        for final_status in ("ENABLED", "PROCESSING", "DISABLED"):
            with self.subTest(final_status=final_status):
                api = FakeAPI(existing=False, status="PROCESSING")
                original = api.request

                def request(method, path, body=None):
                    if method == "GET" and path == "/v1/devices/new-device":
                        return {"data": {"id": "new-device", "attributes": {"status": final_status}}}
                    return original(method, path, body)

                with patch.object(api, "request", side_effect=request) as calls:
                    if final_status == "ENABLED":
                        self.sync(api)
                        self.assertEqual(api.posts[-1][1], "/v1/profiles")
                    else:
                        with self.assertRaises(signing.SigningError):
                            self.sync(api)
                        self.assertEqual([post[1] for post in api.posts], ["/v1/devices"])
                    calls.assert_any_call("GET", "/v1/devices/new-device")

    def test_matching_active_profile_reused_without_mutations(self):
        api = FakeAPI()
        self.sync(api)
        name = api.posts[-1][2]["data"]["attributes"]["name"]
        active = {"attributes": {"name": name, "profileState": "ACTIVE", "profileType": "IOS_APP_ADHOC", "profileContent": base64.b64encode(b"reused").decode()}}
        api = FakeAPI(profiles=[active])
        content, _ = self.sync(api)
        self.assertEqual(content, b"reused")
        self.assertEqual(api.posts, [])

    def test_wrong_account_certificate_prevents_any_mutation(self):
        api = FakeAPI(existing=False)
        with patch.object(signing, "certificate_for_team", side_effect=signing.SigningError("wrong team")):
            with self.assertRaises(signing.SigningError):
                signing.sync_profile(api, {UDID: "phone"}, TEAM, BUNDLE, "Hrafnsyn", "certificate", ".")
        self.assertEqual(api.posts, [])

    def test_associated_domains_capability_enabled_for_exact_bundle(self):
        api = FakeAPI()
        candidate = profile()
        candidate["Entitlements"][signing.ASSOCIATED_DOMAINS] = ["*"]
        with patch.object(signing, "certificate_for_team", return_value=b"fixture certificate"), \
                patch.object(signing, "inspect_content", return_value=candidate):
            signing.sync_profile(api, {UDID: "phone"}, TEAM, BUNDLE, "Hrafnsyn", "certificate", ".", ["tracks.example.com"])
        capability = api.posts[0]
        self.assertEqual(capability[1], "/v1/bundleIdCapabilities")
        self.assertEqual(capability[2]["data"]["attributes"], {"capabilityType": "ASSOCIATED_DOMAINS"})
        self.assertEqual(capability[2]["data"]["relationships"]["bundleId"]["data"]["id"], "bundle")

    def test_existing_capability_does_not_mutate_bundle(self):
        api = FakeAPI(capabilities=[{"attributes": {"capabilityType": "ASSOCIATED_DOMAINS"}}])
        signing.ensure_associated_domains(api, "bundle")
        self.assertEqual(api.posts, [])

    def test_old_profile_cannot_be_reused_for_new_domains(self):
        api = FakeAPI()
        self.sync(api)
        name = api.posts[-1][2]["data"]["attributes"]["name"]
        old = {"attributes": {"name": name, "profileState": "ACTIVE", "profileType": "IOS_APP_ADHOC", "profileContent": base64.b64encode(b"old").decode()}}
        candidate = profile()
        candidate["Entitlements"][signing.ASSOCIATED_DOMAINS] = "*"
        api = FakeAPI(profiles=[old], capabilities=[{"attributes": {"capabilityType": "ASSOCIATED_DOMAINS"}}])
        with patch.object(signing, "certificate_for_team", return_value=b"fixture certificate"), \
                patch.object(signing, "inspect_content", return_value=candidate):
            content, _ = signing.sync_profile(api, {UDID: "phone"}, TEAM, BUNDLE, "Hrafnsyn", "certificate", ".", ["tracks.example.com"])
        self.assertEqual(content, b"fixture CMS")
        self.assertEqual([post[1] for post in api.posts], ["/v1/profiles"])

    def test_pagination_is_bounded_and_cross_origin_is_rejected(self):
        api = signing.AppleAPI("not-a-real-token")
        with self.assertRaises(signing.SigningError):
            api.request("GET", "https://attacker.invalid/v1/devices")
        with patch.object(api, "request", return_value={"data": [], "links": {"next": "/v1/devices?page=2"}}) as request:
            with self.assertRaises(signing.SigningError):
                api.list("devices")
            self.assertEqual(request.call_count, 20)

    def test_es256_der_to_jwt_signature(self):
        raw = b"\x30\x46\x02\x21\x00" + b"\x80" * 32 + b"\x02\x21\x00" + b"\x81" * 32
        self.assertEqual(signing.jwt_signature(raw), b"\x80" * 32 + b"\x81" * 32)
        with self.assertRaises(signing.SigningError):
            signing.jwt_signature(b"bad")


class AssociatedDomainTests(unittest.TestCase):
    def test_exact_dns_domains_are_normalized_and_deduplicated(self):
        self.assertEqual(signing.normalize_domains(["TRACKS.example.com", "tracks.example.com"]), ["tracks.example.com"])
        for invalid in [["https://example.com"], ["example.com:443"], ["*.example.com"], ["localhost"],
                        ["127.0.0.1"], ["example.com?mode=developer"], ["user@example.com"], ["example.com/path"],
                        ["example.com\n"], ["example..com"], ["-example.com"], ["éxample.com"], "example.com", [1]]:
            with self.subTest(value=invalid), self.assertRaises(signing.SigningError):
                signing.normalize_domains(invalid)

    def test_profile_must_authorize_requested_domains(self):
        candidate = profile()
        with self.assertRaises(signing.SigningError):
            signing.validate_profile(candidate, {UDID: "phone"}, TEAM, BUNDLE, domains=["example.com"])
        for allowed in ("*", ["*"], ["applinks:example.com"]):
            candidate["Entitlements"][signing.ASSOCIATED_DOMAINS] = allowed
            signing.validate_profile(candidate, {UDID: "phone"}, TEAM, BUNDLE, domains=["example.com"])
        candidate["Entitlements"][signing.ASSOCIATED_DOMAINS] = ["applinks:another.example.com"]
        with self.assertRaises(signing.SigningError):
            signing.validate_profile(candidate, {UDID: "phone"}, TEAM, BUNDLE, domains=["example.com"])

    def test_signed_entitlements_must_match_exact_requested_domains(self):
        candidate = profile()
        entitlements = {**candidate["Entitlements"], signing.ASSOCIATED_DOMAINS: ["applinks:example.com"]}
        signing.validate_app_entitlements(entitlements, candidate, ["example.com"])
        for actual in ([], ["*"], ["applinks:example.com", "applinks:other.example.com"], "applinks:example.com"):
            with self.subTest(actual=actual), self.assertRaises(signing.SigningError):
                signing.validate_app_entitlements({**entitlements, signing.ASSOCIATED_DOMAINS: actual}, candidate, ["example.com"])

    def test_signed_app_identity_and_distribution_mode_must_match(self):
        candidate = profile()
        for change in ({"application-identifier": "OTHER.io.example.fixture"}, {"get-task-allow": True}):
            with self.subTest(change=change), self.assertRaises(signing.SigningError):
                signing.validate_app_entitlements({**candidate["Entitlements"], **change}, candidate, [])

    def test_ipa_verifies_actual_signature_before_reading_signed_domains(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = Path(tmp) / "test.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/App.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": BUNDLE}))
            candidate = profile()
            signed = {**candidate["Entitlements"], signing.ASSOCIATED_DOMAINS: ["applinks:example.com"]}
            with zipfile.ZipFile(ipa) as archive, patch.object(signing.subprocess, "run") as run:
                run.side_effect = [type("Result", (), {"returncode": 0})(),
                                   type("Result", (), {"returncode": 0, "stdout": plistlib.dumps(signed)})()]
                signing.verify_signed_app(archive, candidate, ["example.com"], BUNDLE, tmp)
                self.assertEqual(run.call_args_list[0].args[0][1:4], ["--verify", "--deep", "--strict"])
                self.assertIn("--entitlements", run.call_args_list[1].args[0])
            with zipfile.ZipFile(ipa) as archive, patch.object(signing.subprocess, "run") as run:
                run.return_value.returncode = 1
                with self.assertRaisesRegex(signing.SigningError, "signature is invalid"):
                    signing.verify_signed_app(archive, candidate, ["example.com"], BUNDLE, tmp)
                self.assertEqual(run.call_count, 1)

    def test_unsafe_ipa_paths_are_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = Path(tmp) / "test.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("../outside.txt", b"bad")
            with zipfile.ZipFile(ipa) as archive, self.assertRaises(signing.SigningError):
                signing.verify_signed_app(archive, profile(), [], BUNDLE, tmp)
            self.assertFalse((Path(tmp).parent / "outside.txt").exists())


if __name__ == "__main__":
    unittest.main()
