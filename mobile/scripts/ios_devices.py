#!/usr/bin/env python3
"""Private device-list provisioning for the ad hoc export script (macOS only)."""

import argparse
import base64
import datetime as dt
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile


class SigningError(Exception):
    """An actionable error that contains no credentials or device identifiers."""


ASSOCIATED_DOMAINS = "com.apple.developer.associated-domains"


def normalize_domains(values):
    if not isinstance(values, list) or len(values) > 30:
        raise SigningError("associated_domains must be a list of at most 30 DNS hostnames.")
    domains = []
    for value in values:
        if not isinstance(value, str) or not value.isascii() or len(value) > 253:
            raise SigningError("Associated domains must be exact ASCII DNS hostnames, without URLs, ports or wildcards.")
        value = value.lower()
        labels = value.split(".")
        if len(labels) < 2 or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label) for label in labels):
            raise SigningError("Associated domains must be exact ASCII DNS hostnames, without URLs, ports or wildcards.")
        try:
            ipaddress.ip_address(value)
        except ValueError:
            pass
        else:
            raise SigningError("Associated domains require DNS hostnames, not IP addresses.")
        if value not in domains:
            domains.append(value)
    return sorted(domains)


def read_domains(path):
    if path is None:
        return []
    path = Path(path)
    if not path.is_file() or path.stat().st_size > 16 * 1024:
        raise SigningError("Could not read the associated domains JSON list.")
    return normalize_domains(json.loads(path.read_text()))


def read_devices(path):
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        raise SigningError("Create mobile/signing/devices.txt with one UDID and device name per line.") from None
    devices = {}
    for number, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=1)
        udid = parts[0].upper()
        if not re.fullmatch(r"(?:[A-F0-9]{8}-[A-F0-9]{16}|[A-F0-9]{40})", udid):
            raise SigningError(f"Invalid device identifier on line {number}; use the full UDID.")
        if udid in devices:
            raise SigningError(f"Duplicate device identifier on line {number}; keep one entry per device.")
        name = parts[1].strip() if len(parts) == 2 else f"Hrafnsyn device {len(devices) + 1}"
        if len(name) > 50 or any(ord(c) < 32 for c in name):
            raise SigningError(f"Device name on line {number} must be at most 50 characters without control characters.")
        devices[udid] = name
    if not devices:
        raise SigningError("The device list is empty. Add at least one iPhone or iPad UDID.")
    return devices


def decode_profile(path):
    result = subprocess.run(
        ["/usr/bin/security", "cms", "-D", "-i", str(path)],
        capture_output=True, check=False,
    )
    if result.returncode:
        raise SigningError("Could not decode the provisioning profile; download a fresh profile from Apple.")
    try:
        return plistlib.loads(result.stdout)
    except (plistlib.InvalidFileException, ValueError):
        raise SigningError("Apple returned an invalid provisioning profile.") from None


def validate_profile(profile, devices, team, bundle, certificate=None, exact=False, domains=()):
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime) or expiry.replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc):
        raise SigningError("The provisioning profile has expired; regenerate it before building.")
    entitlements = profile.get("Entitlements", {})
    if team not in profile.get("TeamIdentifier", []):
        raise SigningError("The provisioning profile belongs to a different Apple team.")
    app_id = entitlements.get("application-identifier", "")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if not any(app_id == f"{prefix}.{bundle}" for prefix in prefixes):
        raise SigningError("The provisioning profile does not match the exact app bundle identifier.")
    if entitlements.get("get-task-allow") is not False or profile.get("ProvisionsAllDevices"):
        raise SigningError("Use an Ad Hoc distribution profile, not a development or enterprise profile.")
    if domains:
        allowed = entitlements.get(ASSOCIATED_DOMAINS, [])
        if isinstance(allowed, str):
            allowed = [allowed]
        if not isinstance(allowed, list) or not all(
                "*" in allowed or "applinks:*" in allowed or f"applinks:{domain}" in allowed
                for domain in domains):
            raise SigningError("The provisioning profile does not allow the requested Associated Domains. Enable the capability and regenerate the profile, or use --sync-devices.")
    included = {value.upper() for value in profile.get("ProvisionedDevices", [])}
    missing = set(devices) - included
    if missing:
        raise SigningError(f"The profile is missing {len(missing)} device(s) from the local list. Rebuild with --sync-devices or update the Ad Hoc profile in Apple Developer and download it again.")
    if exact and included != set(devices):
        raise SigningError("The managed profile device list differs from the requested list.")
    certificates = profile.get("DeveloperCertificates", [])
    if not certificates or (certificate is not None and certificate not in certificates):
        raise SigningError("The provisioning profile does not contain the selected distribution certificate.")
    try:
        uuid.UUID(profile.get("UUID", ""))
    except ValueError:
        raise SigningError("The provisioning profile has an invalid UUID.") from None


def find_installed_profile(name, devices, team, bundle, domains=()):
    roots = [
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
    ]
    matches = []
    last_error = None
    for root in roots:
        for path in root.glob("*.mobileprovision"):
            try:
                profile = decode_profile(path)
            except SigningError:
                continue
            if name not in (profile.get("Name"), profile.get("UUID")):
                continue
            try:
                validate_profile(profile, devices, team, bundle, domains=domains)
                matches.append(profile)
            except SigningError as error:
                last_error = error
    if matches:
        return max(matches, key=lambda profile: profile["ExpirationDate"])
    raise last_error or SigningError("No matching installed profile. Install the named Ad Hoc profile in Xcode, or configure Apple API credentials and use --sync-devices.")


def b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def jwt_signature(der):
    # ECDSA P-256 DER has a short SEQUENCE containing exactly two INTEGERs.
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise SigningError("The API key did not produce an ES256 signature.")
    offset = 2
    values = []
    for _ in range(2):
        if offset + 2 > len(der) or der[offset] != 2:
            raise SigningError("The API key did not produce an ES256 signature.")
        length = der[offset + 1]
        part = der[offset + 2:offset + 2 + length]
        offset += 2 + length
        part = part.lstrip(b"\0")
        if not part or len(part) > 32:
            raise SigningError("The API key must be an App Store Connect P-256 key.")
        values.append(part.rjust(32, b"\0"))
    if offset != len(der):
        raise SigningError("The API key did not produce an ES256 signature.")
    return b"".join(values)


def api_token(key_id, issuer, key_path):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    message = f"{header}.{payload}"
    result = subprocess.run(
        ["/usr/bin/openssl", "dgst", "-sha256", "-sign", str(Path(key_path).expanduser())],
        input=message.encode(), capture_output=True, check=False,
    )
    if result.returncode:
        raise SigningError("Could not sign the Apple API token. Check HRAFNSYN_ASC_KEY_PATH and its file permissions.")
    return f"{message}.{b64url(jwt_signature(result.stdout))}"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class AppleAPI:
    origin = "https://api.appstoreconnect.apple.com"

    def __init__(self, token):
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect)

    def request(self, method, path, body=None):
        url = path if path.startswith("https://") else self.origin + path
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com" or not parsed.path.startswith("/v1/"):
            raise SigningError("Apple returned an unexpected API pagination URL.")
        request = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                         headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"})
        try:
            with self.opener.open(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Never log raw Apple bodies/URLs: either may contain personal identifiers.
            raise SigningError(f"Apple API returned HTTP {error.code}. Check API permissions, membership/device limits and certificate validity; retry after resolving the error in Apple Developer.") from None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            raise SigningError("Could not read the Apple API response. Check connectivity and retry.") from None

    def list(self, resource, **filters):
        query = urllib.parse.urlencode({"limit": 200, **filters})
        path = f"/v1/{resource}?{query}"
        items = []
        for _ in range(20):
            result = self.request("GET", path)
            items.extend(result["data"])
            path = result.get("links", {}).get("next")
            if not path:
                return items
        raise SigningError("Apple returned too many result pages. Narrow the account data before retrying.")


def certificate_for_team(api, certificate_id, team):
    resource = api.request("GET", "/v1/certificates/" + urllib.parse.quote(certificate_id, safe=""))["data"]
    attrs = resource["attributes"]
    if attrs["certificateType"] not in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
        raise SigningError("HRAFNSYN_ASC_CERTIFICATE_ID must identify an Apple/iOS Distribution certificate.")
    expiry = dt.datetime.fromisoformat(attrs["expirationDate"].replace("Z", "+00:00"))
    if expiry <= dt.datetime.now(dt.timezone.utc):
        raise SigningError("The selected distribution certificate has expired; choose a current certificate before syncing devices.")
    cert = base64.b64decode(attrs["certificateContent"], validate=True)
    result = subprocess.run(["/usr/bin/openssl", "x509", "-inform", "DER", "-noout", "-subject", "-nameopt", "sep_multiline"],
                            input=cert, capture_output=True, check=False)
    if result.returncode or not re.search(r"^\s*OU\s*=\s*" + re.escape(team) + r"\s*$", result.stdout.decode(), re.MULTILINE):
        raise SigningError("The selected distribution certificate belongs to a different team or could not be read.")
    return cert


def ensure_associated_domains(api, bundle_id):
    capabilities = api.list(f"bundleIds/{urllib.parse.quote(bundle_id, safe='')}/bundleIdCapabilities")
    if any(item.get("attributes", {}).get("capabilityType") == "ASSOCIATED_DOMAINS" for item in capabilities):
        return
    api.request("POST", "/v1/bundleIdCapabilities", {"data": {
        "type": "bundleIdCapabilities", "attributes": {"capabilityType": "ASSOCIATED_DOMAINS"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}},
    }})


def sync_profile(api, devices, team, bundle, name, certificate_id, output, domains=()):
    # Validate the selected account/certificate before registering any devices.
    certificate = certificate_for_team(api, certificate_id, team)
    bundles = api.list("bundleIds", **{"filter[identifier]": bundle})
    bundles = [item for item in bundles if item["attributes"]["identifier"] == bundle
               and item["attributes"]["platform"] in ("IOS", "UNIVERSAL")]
    if len(bundles) != 1:
        raise SigningError("Create the exact iOS bundle identifier in this Apple developer account before syncing.")
    if domains:
        ensure_associated_domains(api, bundles[0]["id"])
    device_ids = []
    for udid, label in devices.items():
        existing = api.list("devices", **{"filter[udid]": udid, "filter[platform]": "IOS"})
        existing = [item for item in existing if item["attributes"]["udid"].upper() == udid]
        if existing:
            device = existing[0]
        else:
            device = api.request("POST", "/v1/devices", {"data": {"type": "devices", "attributes": {"name": label, "platform": "IOS", "udid": udid}}})["data"]
            # A successful registration may return PROCESSING even when the
            # immediately following read already reports the device enabled.
            if device["attributes"].get("status") == "PROCESSING":
                device = api.request("GET", "/v1/devices/" + urllib.parse.quote(device["id"], safe=""))["data"]
        if device["attributes"].get("status") != "ENABLED":
            raise SigningError("A requested device is disabled or pending with Apple. Resolve its status before rebuilding.")
        device_ids.append(device["id"])

    fingerprint = hashlib.sha256(json.dumps([team, bundle, certificate_id, sorted(devices), sorted(domains)]).encode()).hexdigest()[:12]
    prefix = f"{name[:70]} {fingerprint}"
    for resource in api.list("profiles"):
        attrs = resource["attributes"]
        if not attrs["name"].startswith(prefix + " ") or attrs["profileState"] != "ACTIVE" or attrs["profileType"] != "IOS_APP_ADHOC":
            continue
        content = base64.b64decode(attrs["profileContent"], validate=True)
        try:
            profile = inspect_content(content, output)
            validate_profile(profile, devices, team, bundle, certificate, exact=True, domains=domains)
            return content, profile
        except SigningError:
            continue

    # Apple profiles are immutable; create one for the requested set, never delete/revoke another.
    profile_name = prefix + " " + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
    body = {"data": {"type": "profiles", "attributes": {"name": profile_name, "profileType": "IOS_APP_ADHOC"},
                     "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundles[0]["id"]}},
                                       "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
                                       "devices": {"data": [{"type": "devices", "id": value} for value in device_ids]}}}}
    resource = api.request("POST", "/v1/profiles", body)["data"]
    content = base64.b64decode(resource["attributes"]["profileContent"], validate=True)
    profile = inspect_content(content, output)
    validate_profile(profile, devices, team, bundle, certificate, exact=True, domains=domains)
    return content, profile


def inspect_content(content, directory):
    with tempfile.NamedTemporaryFile(dir=directory, suffix=".mobileprovision") as temporary:
        temporary.write(content)
        temporary.flush()
        return decode_profile(temporary.name)


def validate_app_entitlements(entitlements, profile, domains):
    expected = [f"applinks:{domain}" for domain in domains]
    actual = entitlements.get(ASSOCIATED_DOMAINS, [])
    if not isinstance(actual, list) or sorted(actual) != sorted(expected):
        raise SigningError("The signed app's Associated Domains differ from the requested exact domain list.")
    if entitlements.get("application-identifier") != profile["Entitlements"]["application-identifier"]:
        raise SigningError("The signed app and provisioning profile have different application identifiers.")
    if entitlements.get("get-task-allow", False) is not False:
        raise SigningError("The signed app unexpectedly allows debugging.")


def verify_signed_app(archive, profile, domains, bundle, output):
    members = archive.infolist()
    if len(members) > 20_000 or sum(item.file_size for item in members) > 500 * 1024 * 1024:
        raise SigningError("The exported IPA exceeds the verification size limit.")
    if any(Path(item.filename).is_absolute() or ".." in Path(item.filename).parts
           or stat.S_ISLNK(item.external_attr >> 16) for item in members):
        raise SigningError("The exported IPA contains an unsafe archive entry.")
    with tempfile.TemporaryDirectory(prefix="verify-", dir=output) as temporary:
        archive.extractall(temporary)
        apps = list((Path(temporary) / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise SigningError("The exported IPA must contain exactly one app.")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != bundle:
            raise SigningError("The exported app has the wrong bundle identifier.")
        verified = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], capture_output=True)
        if verified.returncode:
            raise SigningError("The exported app's code signature is invalid.")
        signed = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True)
        if signed.returncode:
            raise SigningError("Could not inspect the exported app's signed entitlements.")
        validate_app_entitlements(plistlib.loads(signed.stdout), profile, domains)


def verify_ipa(path, devices, team, bundle, output, domains=()):
    with zipfile.ZipFile(path) as archive:
        paths = [name for name in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/embedded\.mobileprovision", name)]
        if len(paths) != 1 or archive.getinfo(paths[0]).file_size > 2 * 1024 * 1024:
            raise SigningError("The exported IPA must contain one bounded provisioning profile.")
        profile = inspect_content(archive.read(paths[0]), output)
        validate_profile(profile, devices, team, bundle, domains=domains)
        verify_signed_app(archive, profile, domains, bundle, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "verify"])
    parser.add_argument("--devices", required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--profile")
    parser.add_argument("--output", required=True)
    parser.add_argument("--sync-devices", action="store_true")
    parser.add_argument("--ipa")
    parser.add_argument("--associated-domains-file")
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    devices = read_devices(args.devices)
    domains = read_domains(args.associated_domains_file)
    if args.command == "verify":
        verify_ipa(args.ipa, devices, args.team, args.bundle, output, domains)
        print(f"Exported IPA signature and domains verified; covers all {len(devices)} listed device(s).")
        return
    if args.sync_devices:
        names = ["HRAFNSYN_ASC_KEY_ID", "HRAFNSYN_ASC_ISSUER_ID", "HRAFNSYN_ASC_KEY_PATH", "HRAFNSYN_ASC_CERTIFICATE_ID"]
        missing = [name for name in names if not os.environ.get(name)]
        if missing:
            raise SigningError("Automatic device registration needs " + ", ".join(missing) + ". See docs/mobile.md; do not put private keys in tracked files.")
        key_id, issuer, key_path, certificate_id = [os.environ[name] for name in names]
        api = AppleAPI(api_token(key_id, issuer, key_path))
        content, profile = sync_profile(api, devices, args.team, args.bundle, args.profile, certificate_id, output, domains)
        target = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
        target.mkdir(parents=True, exist_ok=True)
        profile_file = target / f"{profile['UUID']}.mobileprovision"
        with tempfile.NamedTemporaryFile(dir=target, delete=False) as temporary:
            temporary.write(content)
            temp_path = Path(temporary.name)
        try:
            os.replace(temp_path, profile_file)
        finally:
            temp_path.unlink(missing_ok=True)
    else:
        profile = find_installed_profile(args.profile, devices, args.team, args.bundle, domains)
    (output / "signing-profile.txt").write_text(profile["UUID"] + "\n")
    (output / "signing-application-identifier.txt").write_text(profile["Entitlements"]["application-identifier"] + "\n")
    entitlements = {ASSOCIATED_DOMAINS: [f"applinks:{domain}" for domain in domains]} if domains else {}
    (output / "signing.entitlements").write_bytes(plistlib.dumps(entitlements))
    print(f"Provisioning profile verified for {len(devices)} listed device(s).")


if __name__ == "__main__":
    try:
        main()
    except SigningError as error:
        print(f"Signing setup: {error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile):
        print("Signing setup: could not read signing data. Check the local paths and Apple API configuration; no credentials or device data were logged.", file=sys.stderr)
        sys.exit(1)
