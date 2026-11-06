"""Run with nix develop -c python3 -m unittest discover -s mobile/scripts -p 'test_ios_devices.py'."""

import base64
import datetime as dt
from pathlib import Path
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
    def __init__(self, existing=True, status="ENABLED", profiles=None):
        self.existing = existing
        self.status = status
        self.profiles = profiles or []
        self.posts = []

    def list(self, resource, **filters):
        if resource == "bundleIds":
            return [{"id": "bundle", "attributes": {"identifier": BUNDLE, "platform": "IOS"}}]
        if resource == "devices":
            if self.existing:
                return [{"id": "device", "attributes": {"udid": UDID, "status": self.status}}]
            return []
        if resource == "profiles":
            return self.profiles
        raise AssertionError(resource)

    def request(self, method, path, body=None):
        self.posts.append((method, path, body))
        if path == "/v1/devices":
            return {"data": {"id": "new-device", "attributes": {**body["data"]["attributes"], "status": self.status}}}
        if path == "/v1/profiles":
            return {"data": {"attributes": {"profileContent": base64.b64encode(b"fixture CMS").decode()}}}
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
            with patch.object(signing, "inspect_content", return_value=profile()) as inspect:
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

    def test_disabled_or_pending_devices_never_get_a_profile(self):
        for status in ["DISABLED", "PROCESSING"]:
            api = FakeAPI(status=status)
            with self.assertRaises(signing.SigningError):
                self.sync(api)
            self.assertEqual(api.posts, [])

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


if __name__ == "__main__":
    unittest.main()
