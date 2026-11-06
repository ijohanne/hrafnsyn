# Publish a private iOS build

The release command fetches the signed-in administrator's collected device IDs,
merges them with the local device list, exports a signed Ad Hoc IPA, checks its
embedded profile, and uploads it to Hrafnsyn. The device page serves only the
current build to signed-in users. Uploading a new build replaces the old one.

## Configure this Mac once

You need Xcode, an Apple Developer Program membership, an installed Apple
Distribution certificate with its private key, and either an installed Ad Hoc
profile covering the devices or Apple API credentials to update that profile.
See [the signing setup](mobile.md#sharing-with-friends-using-ad-hoc-distribution).

Sign in to Hrafnsyn with an administrator account and open `/users/tokens`.
Create a token for this release workflow and copy its **refresh token** into
`mobile/signing/release.json`. The entire `mobile/signing/` directory is ignored
by Git. Do not place the file in a tracked directory or paste its contents into
logs or issues.

```json
{
  "server_url": "https://tracks.example.com",
  "refresh_token": "PASTE_THE_REFRESH_TOKEN_HERE",
  "team_id": "YOUR_APPLE_TEAM_ID",
  "profile_name": "Hrafnsyn Ad Hoc",
  "bundle_id": "io.hrafnsyn.mobile",
  "sync_devices": false
}
```

The command sets this file to owner-only permissions and replaces the saved
refresh token whenever it rotates. Keep the file writable and avoid restoring
an old copy: a previously rotated token cannot be reused. A lock prevents two
release commands from rotating the same token concurrently.

With `sync_devices: false`, install the named Ad Hoc provisioning profile in
Xcode first. The build stops if it does not cover all requested devices.

To register newly collected devices and regenerate the managed profile through
Apple's API, use `sync_devices: true` and add:

```json
"apple": {
  "key_id": "YOUR_APPLE_API_KEY_ID",
  "issuer_id": "YOUR_APPLE_ISSUER_ID",
  "key_path": "AuthKey_YOUR_KEY_ID.p8",
  "certificate_id": "YOUR_APPLE_DISTRIBUTION_CERTIFICATE_ID"
}
```

This is an additional field in the same JSON object, not a separate file.
`key_path` is relative to `release.json`, or can be absolute. Keep the `.p8` file
private and outside version control. The same four values may instead come
from the `HRAFNSYN_ASC_*` environment variables documented in the signing guide.
Configuration is parsed as JSON; it is never executed as shell code.

## Release

From the repository:

```fish
fish mobile/scripts/release-ios.fish
```

From another directory, use the script's absolute path. It enters this
repository's Nix developer shell automatically. An alternate private JSON file
can be selected with `--config /absolute/path/release.json`.

The command reads only **your own collected invitations** from the configured
server. It also includes entries in `mobile/signing/devices.txt`, when present:

```text
# One UDID and optional name per line; never commit real device identifiers.
00008110-0000000000000001 Example iPhone
```

Local entries are retained and their names take precedence for duplicate device
IDs. Labels fetched from the server are shortened to Apple's device-name limit.
The original local list is never overwritten. An empty combined list stops the
release before building.

Each run rebuilds the shared Rust core and exports into a fresh temporary
directory, so a stale core or older IPA cannot be uploaded accidentally. The
signed IPA is verified before upload. The command
refreshes its session again after building because Xcode may outlast the short
access-token lifetime, then streams the file to the server. Temporary device
lists and build output are removed after the run. A successful upload is
reported only after the server confirms publication.

## Recovery and limits

- A signing or build failure uploads nothing. Correct the reported problem and
  run the command again; the rotated refresh token has already been saved.
- A network failure during upload can leave its outcome uncertain. Check the
  device page before retrying.
- If token rotation succeeds but saving the new token fails, create another
  refresh token in `/users/tokens` and replace the one in the private JSON file.
- Only admins can use these release APIs. The browser download still requires
  a signed-in account, and each device must be covered by the IPA's provisioning
  profile. Downloading an IPA does not itself install it on iOS.
- The upload limit is 250 MiB. HTTPS and normal certificate verification are
  required; redirects are rejected without forwarding credentials. For local
  development only, `allow_loopback_http: true` permits HTTP on `localhost` or a
  loopback IP address.

Protocol and orchestration tests use synthetic data and mocked signing. A real
Apple account, certificate and distribution profile are required to verify a
complete signed release on a physical device.
