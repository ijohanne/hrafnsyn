#!/usr/bin/env python3
"""Fetch owned device IDs, export a signed IPA, and publish one private build."""

import argparse
from contextlib import contextmanager
import fcntl
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import ssl
import stat
import subprocess
import sys
import tempfile
import unicodedata
from urllib.parse import urlsplit

from ios_devices import SigningError, read_devices


MAX_IPA_BYTES = 250 * 1024 * 1024
MAX_RESPONSE_BYTES = 1024 * 1024
UDID = re.compile(r"(?:[A-F0-9]{8}-[A-F0-9]{16}|[A-F0-9]{40})\Z")
APPLE_ENV = {
    "key_id": "HRAFNSYN_ASC_KEY_ID",
    "issuer_id": "HRAFNSYN_ASC_ISSUER_ID",
    "key_path": "HRAFNSYN_ASC_KEY_PATH",
    "certificate_id": "HRAFNSYN_ASC_CERTIFICATE_ID",
}


class ReleaseError(Exception):
    """A safe operational message without response bodies or credentials."""


def validate_origin(value, allow_loopback_http=False):
    if not isinstance(value, str) or not value or any(c.isspace() or ord(c) < 32 for c in value):
        raise ReleaseError("server_url must be an HTTPS origin without spaces.")
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError:
        raise ReleaseError("server_url contains an invalid host or port.") from None
    if (not parsed.hostname or parsed.username is not None or parsed.password is not None
            or parsed.query or parsed.fragment or parsed.path not in ("", "/")
            or port == 0):
        raise ReleaseError("server_url must contain only the server origin, without credentials, path, query or fragment.")
    loopback = parsed.hostname == "localhost"
    try:
        loopback = loopback or ipaddress.ip_address(parsed.hostname).is_loopback
    except ValueError:
        pass
    if parsed.scheme != "https" and not (parsed.scheme == "http" and allow_loopback_http and loopback):
        raise ReleaseError("HTTPS is required. HTTP is allowed only for explicit loopback development.")
    return parsed


def clean_token(value):
    if not isinstance(value, str) or not value or len(value) > 8192 or any(c.isspace() or ord(c) < 33 or ord(c) > 126 for c in value):
        raise ReleaseError("The server returned an invalid authentication token.")
    return value


def load_config(path):
    if path.is_symlink():
        raise ReleaseError("Use a regular private release.json file, not a symbolic link.")
    try:
        if not path.is_file() or path.stat().st_size > 64 * 1024:
            raise ReleaseError("Create mobile/signing/release.json using docs/ios-release.md.")
        config = json.loads(path.read_text())
    except (OSError, ValueError):
        raise ReleaseError("Could not read release.json. Use the JSON example in docs/ios-release.md.") from None
    if not isinstance(config, dict):
        raise ReleaseError("release.json must contain a JSON object.")
    for name in ("team_id", "profile_name", "bundle_id"):
        value = config.get(name)
        if not isinstance(value, str) or not value.strip() or any(ord(c) < 32 for c in value):
            raise ReleaseError(f"Set {name} in release.json.")
    for name in ("sync_devices", "allow_loopback_http"):
        if name in config and not isinstance(config[name], bool):
            raise ReleaseError(f"{name} must be true or false.")
    validate_origin(config.get("server_url"), config.get("allow_loopback_http", False))
    clean_token(config.get("refresh_token"))
    os.chmod(path, 0o600)
    return config


@contextmanager
def release_lock(path):
    try:
        descriptor = os.open(str(path) + ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        os.fchmod(descriptor, 0o600)
    except OSError:
        raise ReleaseError("Could not open the release lock beside release.json.") from None
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ReleaseError("Another release is using this configuration. Wait for it to finish.") from None
        yield
    finally:
        os.close(descriptor)


def save_rotated_token(path, config, token):
    updated = {**config, "refresh_token": clean_token(token)}
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".release-", delete=False) as output:
            temporary = Path(output.name)
            os.fchmod(output.fileno(), 0o600)
            json.dump(updated, output, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except OSError:
        raise ReleaseError("The session rotated but its new token could not be saved. Create a new token in Hrafnsyn and update release.json before retrying.") from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return updated


class ReleaseAPI:
    def __init__(self, config):
        self.origin = validate_origin(config["server_url"], config.get("allow_loopback_http", False))

    def connection(self):
        if self.origin.scheme == "https":
            return http.client.HTTPSConnection(self.origin.hostname, self.origin.port, timeout=60,
                                               context=ssl.create_default_context())
        return http.client.HTTPConnection(self.origin.hostname, self.origin.port, timeout=60)

    @staticmethod
    def response(connection, expected):
        response = connection.getresponse()
        if response.status != expected:
            if 300 <= response.status < 400:
                raise ReleaseError("Hrafnsyn redirected the API request. Set its final HTTPS origin in release.json; credentials were not forwarded.")
            raise ReleaseError(f"Hrafnsyn API returned HTTP {response.status}. Check the admin token, server version and upload limit.")
        data = response.read(MAX_RESPONSE_BYTES + 1)
        if len(data) > MAX_RESPONSE_BYTES:
            raise ReleaseError("Hrafnsyn returned an unexpectedly large API response.")
        try:
            result = json.loads(data)
        except ValueError:
            raise ReleaseError("Hrafnsyn returned invalid API data.") from None
        if not isinstance(result, dict):
            raise ReleaseError("Hrafnsyn returned invalid API data.")
        return result

    def request(self, method, path, token):
        connection = self.connection()
        try:
            connection.request(method, path, body=b"" if method == "POST" else None,
                               headers={"Authorization": "Bearer " + clean_token(token), "Accept": "application/json"})
            return self.response(connection, 200)
        except (OSError, http.client.HTTPException):
            raise ReleaseError("Could not reach Hrafnsyn securely. Check connectivity and the configured server.") from None
        finally:
            connection.close()

    def upload(self, path, token):
        boundary = "hrafnsyn-" + secrets.token_hex(24)
        prefix = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"ipa\"; filename=\"Hrafnsyn.ipa\"\r\n"
                  "Content-Type: application/octet-stream\r\n\r\n").encode("ascii")
        suffix = f"\r\n--{boundary}--\r\n".encode("ascii")
        connection = self.connection()
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, "rb") as source:
                info = os.fstat(source.fileno())
                if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_IPA_BYTES:
                    raise ReleaseError("The exported IPA must be a regular file no larger than 250 MiB.")
                connection.putrequest("POST", "/api/mobile-release/ipa")
                connection.putheader("Authorization", "Bearer " + clean_token(token))
                connection.putheader("Accept", "application/json")
                connection.putheader("Content-Type", "multipart/form-data; boundary=" + boundary)
                connection.putheader("Content-Length", str(len(prefix) + info.st_size + len(suffix)))
                connection.endheaders()
                connection.send(prefix)
                remaining = info.st_size
                while remaining:
                    chunk = source.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ReleaseError("The exported IPA changed during upload. Run the release again.")
                    connection.send(chunk)
                    remaining -= len(chunk)
                connection.send(suffix)
            result = self.response(connection, 201)
            if result.get("status") != "published":
                raise ReleaseError("Hrafnsyn did not confirm that the IPA was published.")
        except (OSError, http.client.HTTPException):
            raise ReleaseError("The IPA upload could not be completed. Check the device page before retrying; the server may already have received it.") from None
        finally:
            connection.close()


def collected_devices(response):
    rows = response.get("devices")
    if not isinstance(rows, list) or len(rows) > 10_000:
        raise ReleaseError("Hrafnsyn returned an invalid device list.")
    devices = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("udid"), str):
            raise ReleaseError("Hrafnsyn returned an invalid device identifier.")
        udid = row["udid"].upper()
        if not UDID.fullmatch(udid):
            raise ReleaseError("Hrafnsyn returned an invalid device identifier.")
        name = row.get("name")
        if not isinstance(name, str):
            raise ReleaseError("Hrafnsyn returned an invalid device name.")
        name = "".join(" " if unicodedata.category(c).startswith("C") else c for c in name)
        devices[udid] = " ".join(name.split())[:50] or "Hrafnsyn device"
    return devices


def merge_devices(server_devices, local_path):
    local = {}
    if local_path.exists():
        if any(line.strip() and not line.lstrip().startswith("#") for line in local_path.read_text().splitlines()):
            try:
                local = read_devices(local_path)
            except SigningError as error:
                raise ReleaseError(str(error)) from None
    merged = {**server_devices, **local}
    if not merged:
        raise ReleaseError("No collected or local devices are available. Collect a UDID first or add one to mobile/signing/devices.txt.")
    return merged


def signing_environment(config, config_path):
    environment = os.environ.copy()
    apple = config.get("apple", {})
    if not isinstance(apple, dict) or set(apple) - set(APPLE_ENV):
        raise ReleaseError("apple must contain only key_id, issuer_id, key_path and certificate_id.")
    for key, value in apple.items():
        if not isinstance(value, str) or not value.strip() or any(ord(c) < 32 for c in value):
            raise ReleaseError(f"The Apple {key} setting is invalid.")
        if key == "key_path":
            value = str((config_path.parent / Path(value).expanduser()).resolve())
        environment[APPLE_ENV[key]] = value
    if config.get("sync_devices") and any(not environment.get(name) for name in APPLE_ENV.values()):
        raise ReleaseError("Automatic signing sync needs all four Apple settings. See docs/ios-release.md.")
    return environment


def run_checked(command, environment, repo, failure):
    result = subprocess.run(command, cwd=repo, env=environment, check=False)
    if result.returncode:
        raise ReleaseError(failure)


def release(repo, config_path, api_factory=ReleaseAPI):
    with release_lock(config_path):
        config = load_config(config_path)
        environment = signing_environment(config, config_path)
        api = api_factory(config)
        session = api.request("POST", "/api/mobile-release/session", config["refresh_token"])
        # Persist the rotated credential before a device lookup, signing or build can fail.
        config = save_rotated_token(config_path, config, session.get("refresh_token"))
        access = clean_token(session.get("access_token"))
        devices = merge_devices(collected_devices(api.request("GET", "/api/mobile-release/devices", access)),
                                repo / "mobile/signing/devices.txt")
        print(f"Preparing a build for {len(devices)} device(s).", flush=True)
        root = repo / "mobile/build/releases"
        root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="release-", dir=root) as temporary:
            work = Path(temporary)
            device_file = work / "devices.txt"
            with device_file.open("x") as output:
                os.chmod(device_file, 0o600)
                output.writelines(f"{udid}\t{name}\n" for udid, name in sorted(devices.items()))
            output_dir = work / "signed"
            signing = ["--devices-file", str(device_file), "--output-dir", str(output_dir)]
            if config.get("sync_devices"):
                signing.append("--sync-devices")
            run_checked(["fish", str(repo / "mobile/scripts/build-core.fish")], environment, repo,
                        "Shared iOS core build failed. Nothing was exported or uploaded.")
            run_checked(["fish", str(repo / "mobile/scripts/export-adhoc.fish"), *signing,
                         config["team_id"], config["profile_name"], config["bundle_id"]], environment, repo,
                        "iOS export failed. Nothing was uploaded; resolve the signing/build error and run again.")
            ipas = list((output_dir / "export").glob("*.ipa"))
            if len(ipas) != 1 or ipas[0].is_symlink() or not ipas[0].is_file():
                raise ReleaseError("Expected one newly exported IPA. Nothing was uploaded.")
            run_checked([sys.executable, str(repo / "mobile/scripts/ios_devices.py"), "verify",
                         "--devices", str(device_file), "--team", config["team_id"], "--bundle", config["bundle_id"],
                         "--output", str(output_dir), "--ipa", str(ipas[0])], environment, repo,
                        "Exported IPA verification failed. Nothing was uploaded.")
            # Signing can outlast the short-lived access token. Rotate again immediately
            # before publishing, saving it with the same lock and atomic replacement.
            session = api.request("POST", "/api/mobile-release/session", config["refresh_token"])
            config = save_rotated_token(config_path, config, session.get("refresh_token"))
            api.upload(ipas[0], clean_token(session.get("access_token")))
        print("IPA published. Signed-in users can download it from the device page.", flush=True)


def main():
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=repo / "mobile/signing/release.json")
    args = parser.parse_args()
    release(repo, args.config.absolute())


if __name__ == "__main__":
    try:
        main()
    except ReleaseError as error:
        print(f"Release: {error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, TypeError, KeyError):
        print("Release: could not read local release data. Check paths, permissions and configuration; no credentials were logged.", file=sys.stderr)
        sys.exit(1)
