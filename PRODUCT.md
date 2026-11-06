# Hrafnsyn

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Product Purpose

Unified aircraft and vessel tracking. Merge ADS-B and AIS sources onto one realtime map, with searchable identities, track history, and recent observation logs.

## Users and Operating Context

The user confirmed a frequently used tracking workspace with the map and quick inspection taking priority. Search, routes, and logs must stay close at hand.

## Capabilities and Constraints

- Preserve multiple upstream sources and the existing Phoenix LiveView web application.
- Public access is read only; server administrators manage accounts.
- Native iOS app connects to a configurable server over the existing gRPC protocol, discovers login requirements, and remembers sessions securely.
- Support iPhone and iPad, using larger iPads for simultaneous browsing, mapping, and inspection.
- Native Android uses Kotlin, Jetpack Compose and MapLibre, with adaptive phone and tablet layouts.
- Share the protocol, gRPC transport, authentication and domain records through a Rust core with Swift/Kotlin bindings; platform screens and secure storage remain native.

## Brand Commitments

Keep the Hrafnsyn name and existing logo. No additional aesthetic commitments were supplied.

## Evidence on Hand

The current dashboard, tracking and authentication gRPC contract, server implementation, and tests are the product authority. Source configuration alone does not prove collector health.

## Product Principles

- Prioritize the map and rapid inspection.
- Preserve clear distinction between aircraft and vessels.
- Expose real connection, empty, and authentication states.
- Use larger screens to show useful simultaneous context.
