---
version: 1
slug: "mobile-android-app-mainactivity-kt"
primary_target: "mobile/android/app/src/main/java/io/hrafnsyn/mobile/MainActivity.kt"
related_targets: ["mobile/android/app/src/main/java/io/hrafnsyn/mobile/TrafficMap.kt", "mobile/android/app/src/main/java/io/hrafnsyn/mobile/TrackingModel.kt"]
---

# Native Android traffic client

Mode: Operate. Native Android extension of the approved map-first tracking product. Reuse the Rust gRPC and domain core through Kotlin bindings; retain Android navigation, rendering, lifecycle and secure storage.

## Direction contract

THESIS: Put geography and quick inspection first. Phones keep a full map with a traffic view and native detail sheet; wide windows show traffic and map together, with an additional inspector when space permits.

OWN-WORLD: Existing Hrafnsyn raven-eye identity, Android system typography, Material controls, semantic light/dark surfaces and a teal accent. Distinguish aircraft and vessels through both text and symbols.

STORY: Enter a server, discover its access policy and sign in only when required. Remember tokens in Keystore-backed encrypted storage without saving passwords. Show connection failures, retry, empty traffic, server changes and sign-out directly.

FIRST VIEWPORT: A focused server form before connection; a map with Traffic and Server actions after connection. Wide screens provide simultaneous useful context. Keyboard, font scaling, system bars and window resizing must remain usable.

FORM: Kotlin/Jetpack Compose and native MapLibre extension of the approved product direction (web reference seed:864dc47a20baf46f). No new direction chooser or shared screen toolkit.

FINISH: End with independent screenshot review and an explicit verdict; document the implemented system in DESIGN.md and its sidecar. Shipping raster assets retain their provenance.
