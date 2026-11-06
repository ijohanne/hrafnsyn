# Native mobile clients

Hrafnsyn's applications live in `mobile/ios` and `mobile/android`; their shared Rust core in `mobile/core` uses the canonical `proto/hrafnsyn/v1/tracking.proto` at build time. UniFFI emits Swift and Kotlin bindings, reusing transport, server normalization, authentication/refresh and domain records. SwiftUI, MapKit and Keychain remain native iOS responsibilities. Android uses Kotlin, Jetpack Compose, MapLibre and Android Keystore. Each platform owns screen composition and lifecycle. See `mobile/README.md` and `mobile/android/README.md` for build and verification commands.

## iPhone and iPad

The app supports iOS/iPadOS 18+, both light and dark appearance and Dynamic Type. A compact window uses a map with traffic/details sheets. A regular-width window uses `NavigationSplitView` with a persistent searchable traffic list, map, and track inspector. Resizing and iPad multitasking follow the current size class rather than device name. Existing server identities and tracking values are displayed without invented content.

The server selector defaults to HTTPS; only loopback may use unencrypted HTTP for local development. The gRPC port is independent of the web port. The client discovers access requirements with `AuthService.GetAuthStatus`. Public servers bypass login. Protected servers use the existing username/password RPC; no account-creation or third-party sign-in endpoint is assumed. Access and refresh tokens are scoped to a canonical server origin and saved to device-only Keychain. Passwords are never saved. The core serializes refresh rotation; the platform persists the latest pair after every operation, even if the subsequent tracking operation fails. Session revocation is attempted on sign-out, with a clear local-only warning if the server is unreachable.

The current app uses foreground unary gRPC polling, five seconds normally and 15 seconds during reconnect; it pauses in the background. Server streaming and offline historical storage are future improvements, not simulated capabilities. TLS checks public WebPKI roots; private CA enrollment is not implemented.

## Android phones and tablets

The Android 8+ app uses native Compose screens and MapLibre, with ARM64 and x86_64
libraries. Phones offer a map, searchable traffic view and detail sheet. Windows
at least 840dp wide keep a sidebar beside the map; at 1200dp a separate inspector
can appear alongside both. Appearance, font scaling and system insets follow the
platform.

Android stores encrypted tokens with an Android Keystore key, bound to their
canonical server origin and excluded from cloud and device-transfer backups.
Process-wide client ownership coordinates refresh persistence across screen
recreation. Passwords are never saved. The same core supplies authentication
discovery, login, refresh, tracking and six-hour routes to both native apps.

Build and install instructions, SDK prerequisites and release signing are in
[`mobile/android/README.md`](../mobile/android/README.md). A development APK can be
shared directly for testing; Android does not use an Apple-style UDID list.
Use a stable private signing key for release updates, and keep it outside source
control. The production server address is `https://hrafnsyn.unixpimps.net` when its
nginx gRPC routing is enabled; a separate port is unnecessary in that deployment.

## Sharing with friends using Ad Hoc distribution

### Collect UDIDs through Hrafnsyn

No cable or Mac is needed for this collection step. Sign in to Hrafnsyn, open
**iOS devices** from the account menu (`/users/devices`), name an invitation for
one iPhone or iPad, and share its link with that device's owner. The friend opens
the link in Safari, downloads the profile, and approves it under **Settings →
General → VPN & Device Management** (or **Profile Downloaded**). The profile is
unsigned, so iOS shows **Not Signed**. It requests only the UDID and sends it to
this Hrafnsyn server; it does not install the app or enroll the device in device
management.

After collection, refresh **iOS devices** to copy the UDID. Register it in your
Apple developer account, update the Ad Hoc provisioning profile, and export a
new IPA as described below. Collecting an identifier does not perform these
Apple registration or signing steps automatically. Use a separate invitation
for each device, including a friend's iPhone and iPad.

Links expire after seven days. Each account can keep 25 invitations; **Delete**
invalidates the link and removes any collected UDID. Records become eligible
for removal 30 days after invitation creation, with global cleanup running
hourly. See [device registration](device-registration.md) for the full flow,
retention details, HTTPS/proxy requirements and verification boundaries.

### Your own iPhone and iPad

You do not need to collect or send UDIDs manually when running directly from
Xcode with automatic signing. Build the core, open
`mobile/ios/Hrafnsyn.xcodeproj`, select the app target's **Signing & Capabilities**,
choose your Apple account/team and enable **Automatically manage signing**.
Connect and trust your device, enable Developer Mode if prompted, select the
physical device as the run destination, and run. Repeat for the other device.
Xcode registers connected devices and manages their development profiles.

A free Apple account can use a Personal Team for this purpose. Its provisioning
profiles expire after seven days, requiring another build/install; Apple also
limits the number of personal-team devices and apps. A paid developer membership
is needed for the Ad Hoc distribution workflow below. Owning a device does not
exempt it from the registered-device list in an Ad Hoc profile.

As an alternative to the Hrafnsyn collection link, collect a UDID with Finder:

1. Connect the iPhone or iPad to your Mac and select it under Finder's Locations.
2. Complete the Trust prompts on the Mac/device if shown.
3. Click the device information below its name until the UDID appears.
4. Control-click it and choose **Copy UDID**. Record a descriptive device name
   alongside it, separately for the iPhone and iPad.

Xcode 27's Device Hub also exposes this under the selected device's Info
inspector; enable the UDID field in Edit Visibility if hidden. Keep device lists
outside source control. See Apple's [identifier instructions](https://developer.apple.com/documentation/xcode/locating-device-identifiers)
and [Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

### Export a distributable IPA

An Apple Developer Program membership is required. Register the intended iPhone/iPad UDIDs in your developer account, create an explicit App ID for your chosen bundle identifier, and create an **Ad Hoc distribution provisioning profile** that includes those devices and an Apple Distribution certificate whose private key is installed in your Mac's Keychain. This does not require App Store publication.

For the configured-instance workflow that collects your device IDs, builds and uploads in one command, see [the iOS release workflow](ios-release.md).

1. Add the intended devices to **`mobile/signing/devices.txt`**, one UDID followed by a descriptive name per line. Blank lines and `#` comments are supported. This entire directory is gitignored; keep device identifiers and API keys there or outside the checkout, never in tracked examples. The file is required, not an optional check: the export fails if it is absent or empty.
2. Build the shared core with `nix develop -c fish mobile/scripts/build-core.fish`.
3. Install the distribution certificate/private key and downloaded provisioning profile through Xcode. Choose your own bundle identifier if `io.hrafnsyn.mobile` is unavailable in your team.
4. Export a signed IPA:

   ```fish
   nix develop -c fish mobile/scripts/export-adhoc.fish YOUR_TEAM_ID 'Your Ad Hoc profile name' your.bundle.identifier
   ```

5. The archive, generated `ExportOptions.plist`, and IPA are placed under ignored `mobile/build/ad-hoc/`. Share the exported IPA only with registered testers. They can install it with Xcode or Apple Configurator on a connected device. An OTA installation page additionally requires your own HTTPS hosting and a correctly generated manifest; this export command does not publish anything.

Every export reads the local device list, checks the profile before archiving, selects its exact UUID and checks the profile embedded in the final IPA. The checks include the team, exact bundle ID, expiration, distribution settings and every listed device. A stale profile fails with an actionable error before the expensive build. Override the input with `--devices-file PATH` (or `HRAFNSYN_IOS_DEVICES_FILE`); `--output-dir PATH` isolates a release's artifacts. These overrides support the one-command workflow without changing your local list.

The script uses Xcode's `release-testing` export method (the current name for the deprecated `ad-hoc` option) and manual signing. The default command does not change your Apple account. A newly added device requires an updated profile and another export/build, either manually or using the opt-in sync below. Signed builds stop working when their profile expires. Apple limits the number of registered devices per product family per membership year.

### Register listed devices automatically

Use an App Store Connect **team API key with access to Certificates, Identifiers & Profiles**, your issuer ID and an existing Apple Distribution certificate. The certificate's private key must already be installed on the build Mac; the API key does not replace it. Set these variables locally in fish (the key path points to the downloaded `.p8`, not its contents):

```fish
set -gx HRAFNSYN_ASC_KEY_ID YOUR_KEY_ID
set -gx HRAFNSYN_ASC_ISSUER_ID YOUR_ISSUER_ID
set -gx HRAFNSYN_ASC_KEY_PATH /private/path/AuthKey_YOUR_KEY_ID.p8
set -gx HRAFNSYN_ASC_CERTIFICATE_ID YOUR_CERTIFICATE_RESOURCE_ID
nix develop -c fish mobile/scripts/export-adhoc.fish --sync-devices YOUR_TEAM_ID 'Hrafnsyn Ad Hoc' your.bundle.identifier
```

The explicit `--sync-devices` flag authorizes registration of missing devices from the file. It validates the selected certificate's team first, checks registered device status, and reuses an active matching profile or creates a new Ad Hoc profile for the exact requested device set. The profile is downloaded into Xcode's provisioning directory. It never disables devices, revokes certificates or deletes existing profiles. Apple may require waiting or account action for devices that are not yet enabled. New registrations consume Apple's device quota; removing a line locally does not unregister that device.

The helper uses Apple's [device registration](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-devices), [profile creation](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-profiles) and [ES256 authentication](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests) APIs. Tokens, private key contents and UDIDs are not printed. API errors report only status and recovery guidance. Protocol behavior is covered by mocked tests; account-specific registration and signed IPA export require your credentials and signing assets.

Run the helper tests with `nix develop -c python3 -m unittest discover -s mobile/scripts -p test_ios_devices.py`.

No signing team, certificate or provisioning profile is embedded in the repository. Simulator builds need none; producing the distributable IPA requires these account-specific inputs.

## Dependency scan

On 2026-11-06, `osv-scanner scan source --lockfile=mobile/core/Cargo.lock --format=json --output-file=mobile/build/cargo-security.json` scanned 208 resolved packages. The report contains one maintenance advisory, **RUSTSEC-2026-0374**, for `basic-toml 0.1.10`. It enters through the optional binding-generation CLI: `askama_derive 0.16.1` → `askama_macros` → `askama` → `uniffi_bindgen 0.32.2`. These are the current resolved upstream releases; the advisory is not suppressed or waived.

`cargo tree -i basic-toml` without the `bindings` feature prints no dependency path; `cargo tree --features bindings -i basic-toml` shows the CLI path. The device/simulator libraries are built without that feature. This distinguishes the build-tool exposure from the shipped runtime; the full lockfile scan still exits nonzero and should continue to be reported. Updating tonic to 0.14 removed the earlier `rustls-pemfile` maintenance advisory. The scanner JSON is an ignored local verification artifact, not a committed security exception.

Official Apple guidance: [Create an Ad Hoc provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/), [register devices and annual limits](https://developer.apple.com/help/account/devices/devices-overview/), and [distribute to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).
