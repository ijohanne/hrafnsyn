# Hrafnsyn mobile

Native SwiftUI + MapKit for iPhone and iPad, and Kotlin + Jetpack Compose + MapLibre for Android phones and tablets, with a Rust gRPC core shared through UniFFI-generated Swift and Kotlin bindings. iOS requires iOS/iPadOS 18 or later. Android requires Android 8 or later. There is no web view or shared UI toolkit. See [Android build and distribution](android/README.md) for APK builds and installation.

From the repository root, on an Apple Silicon Mac with Xcode installed:

```fish
nix develop -c fish mobile/scripts/build-core.fish
nix develop -c fish mobile/scripts/build-ios.fish
```

Open `mobile/ios/Hrafnsyn.xcodeproj` to run or sign the app. The first build downloads a local Rust toolchain into ignored `mobile/.toolchains`; nothing is installed globally. Device and Apple Silicon simulator libraries are assembled into an ignored XCFramework. The Xcode project and generated bindings are committed; regenerate them after changes to the shared core or protobuf contract.

The setup screen accepts the **gRPC** host and port, not the Phoenix HTTP endpoint. TLS is mandatory except for loopback development. Certificates are checked against WebPKI public roots; private/self-signed certificate authorities are not currently supported. Public servers open directly. Restricted servers prompt for a username and password; the password is discarded after submission. Tokens are isolated by canonical server origin and stored in non-synchronizing, device-only Keychain entries. Refresh token rotation is serialized in the shared core and persisted after requests, including failed requests. Revoked/expired credentials return to sign-in.

The app fetches current positions every five seconds while active (15 seconds during reconnect), pauses when backgrounded, and loads six hours of history on selection. This first client uses unary gRPC calls; it does not yet subscribe to `StreamTrackUpdates`. Empty feeds, unreachable servers, retry, search, aircraft/vessel filters, sign-out and changing servers are supported. iPad uses a persistent traffic sidebar, map and selected-track inspector; iPhone uses map-first navigation and native sheets.

## Verification

```fish
nix develop -c fish mobile/scripts/test-core.fish http://localhost:50051
nix develop -c fish mobile/scripts/test-ios.fish YOUR_SIMULATOR_UDID
```

The smoke example connects to a real server and loads active tracks and route history. For restricted servers set `HRAFNSYN_TEST_USERNAME` and `HRAFNSYN_TEST_PASSWORD` in your local environment; it revokes its own session on completion and never prints credentials. Enable a local server by setting `GRPC_PORT=50051` alongside this flake's normal database environment. Do not expose the unencrypted loopback endpoint remotely.

See [distribution and platform architecture](../docs/mobile.md) for Ad Hoc sharing and the shared client architecture.
