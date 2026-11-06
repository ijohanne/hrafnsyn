# Hrafnsyn for Android

Native Kotlin/Jetpack Compose app for Android 8+ (ARM64 phones/tablets and x86_64 emulators). MapLibre Native renders OpenFreeMap tiles with provider attribution. Phones use a map, searchable traffic list and inspection sheet; windows at least 840dp wide keep a sidebar beside the map, and windows at least 1200dp add a separate inspector. Dark mode, font scaling, back navigation, system insets and keyboard resizing follow Android settings.

Enter your server, for example `https://hrafnsyn.unixpimps.net`. The app discovers whether login is required. TLS gRPC, login, token rotation and tracking/route models use the same Rust tonic/UniFFI core as iOS. The UI and platform storage remain native. Remote servers require HTTPS; loopback HTTP is available for development through `adb reverse`.

Passwords are submitted from memory only. Access/refresh pairs are encrypted with an Android Keystore AES-GCM key, authenticated against their canonical server origin, and excluded from cloud/device-transfer backups. Process-wide core ownership prevents old requests overwriting refreshed credentials during screen changes. Started, deadline-bounded requests finish their credential write when a screen is destroyed. Sign out removes local credentials and attempts server revocation.

## Build on Apple Silicon macOS

Run from the repository root using the Nix shell. Use a writable Android SDK (Android Studio's SDK or an ignored checkout-local `mobile/android/.sdk`). Set `HRAFNSYN_ANDROID_SDK` if it is elsewhere. Install these SDK packages with `sdkmanager --sdk_root=PATH` from your SDK command-line tools, reviewing any required license prompts:

```text
platform-tools
platforms;android-36
build-tools;35.0.0
ndk;28.2.13676358
```

Java 17, SDK command-line tools and Rustup can be supplied through Nix; no global package installation is needed. The checked-in Gradle wrapper pins Gradle 8.14 and verifies its distribution SHA-256. Rust dependencies use `mobile/core/Cargo.lock`. These scripts currently target an Apple Silicon Mac host; Android outputs include both ARM64 and x86_64.

```fish
nix develop -c fish mobile/scripts/build-core.fish # regenerate bindings if core changed; also builds iOS
nix develop -c fish mobile/scripts/build-core-android.fish
nix develop -c fish mobile/scripts/build-android.fish
```

The installable development APK is `mobile/android/app/build/outputs/apk/debug/app-debug.apk`. Install using `adb install -r PATH`, or copy it to a friend's Android device and allow installation from the app opening the file. Android sideloading needs no UDID list or App Store account. Debug builds are for testing; keep a stable release signing key before distributing updates broadly.

## Sign a shareable release

Create your private signing key outside this checkout. Keep its password and a secure backup; updates must use the same key. `keytool` prompts for passwords:

```fish
keytool -genkeypair -keystore /secure/location/hrafnsyn.jks -alias hrafnsyn -keyalg RSA -keysize 3072 -validity 10000
set -gx HRAFNSYN_ANDROID_KEYSTORE /secure/location/hrafnsyn.jks
set -gx HRAFNSYN_ANDROID_KEY_ALIAS hrafnsyn
read --silent --prompt-str 'Store password: ' HRAFNSYN_ANDROID_STORE_PASSWORD
set -gx HRAFNSYN_ANDROID_STORE_PASSWORD $HRAFNSYN_ANDROID_STORE_PASSWORD
read --silent --prompt-str 'Key password: ' HRAFNSYN_ANDROID_KEY_PASSWORD
set -gx HRAFNSYN_ANDROID_KEY_PASSWORD $HRAFNSYN_ANDROID_KEY_PASSWORD
nix develop -c fish mobile/scripts/build-android.fish assembleRelease
set -e HRAFNSYN_ANDROID_STORE_PASSWORD
set -e HRAFNSYN_ANDROID_KEY_PASSWORD
```

Share `app/build/outputs/apk/release/app-release.apk`. Without signing environment variables, Gradle deliberately produces an unsigned release. Debug and release keys differ: uninstall the debug app before installing a separately signed release (this clears its saved sessions). Never commit keys, passwords or generated APKs.

## Verify

Use a connected device/emulator for the real Android Keystore tests. For a local public gRPC fixture server, forward its loopback port and include the optional endpoint argument:

```fish
adb reverse tcp:50051 tcp:50051
nix develop -c fish mobile/scripts/build-android.fish connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.hrafnsynGrpcEndpoint=http://127.0.0.1:50051
```

Tests check encrypted token rotation, server isolation, ciphertext tampering through another origin, and the packaged Rust/JNA gRPC transport. The shared core's separate suite verifies conditional login, refresh and revocation against a real in-process gRPC service. Screenshots can be captured with `adb exec-out screencap -p`; exercise phone/tablet widths, dark mode, font scale, server failure and contact inspection. An emulator proves the native build/runtime, not physical-device Keystore hardware or production credentials.

Generated bindings in `generated/` must come from `mobile/scripts/build-core.fish`; do not hand-edit them. The raven-eye launcher asset shares the iOS source; its provenance sidecar is in `artwork/` and embedded metadata is preserved.
