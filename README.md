<p align="center">
  <img src="priv/static/images/logo.svg" alt="Hrafnsyn" width="132">
</p>

<h1 align="center">Hrafnsyn</h1>

<p align="center">
  A Phoenix LiveView command surface for merged ADS-B and AIS situational awareness,
  with realtime map updates, historical route playback, durable logging, and simple opt-in auth.
</p>

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
  - [Nix-first development](#nix-first-development)
  - [Without Nix](#without-nix)
  - [Bootstrap admin](#bootstrap-admin)
- [Runtime Model](#runtime-model)
- [Authentication Model](#authentication-model)
- [Source Configuration](#source-configuration)
- [Reverse Proxy](#reverse-proxy)
- [Observability](#observability)
- [Documentation](#documentation)
- [Roadmap Hooks](#roadmap-hooks)

## Overview

Hrafnsyn merges aircraft and vessel tracking into one responsive map:

- Phoenix 1.8 + LiveView with PubSub-backed realtime updates
- one long-lived GenServer collector per configured upstream source
- PostgreSQL + PostGIS-backed history, search, and route replay
- merged identities across multiple sources of the same vehicle type
- gRPC API for auth, track reads, live update streaming, and ingress
- readonly public mode by default, with lightweight admin-managed users when enabled
- MapLibre frontend with an OpenFreeMap base style
- Prometheus metrics via PromEx, with optional scrape/dashboard provisioning on NixOS

The default greenfield source profile is wired for the two SDR-backed interfaces observed on `2026-04-07`:

- dump1090 / SkyAware style aircraft feed at `http://10.255.101.202`
- AIS-catcher vessel feed at `http://10.255.101.202:8100`

## Architecture

- `Hrafnsyn.Collectors.Supervisor` starts one collector worker per configured source.
- `Hrafnsyn.Collectors.Worker` polls upstream JSON endpoints and normalizes payloads.
- `Hrafnsyn.Ingest` is the stable ingest boundary for current collectors and future transports.
- `Hrafnsyn.Tracking` persists current merged tracks and append-only track points in Postgres.
- `Phoenix.PubSub` fans updates into LiveView so the map and detail panels refresh live.
- `proto/hrafnsyn/v1/tracking.proto` defines the current auth, tracking, and ingress gRPC contract.

More detail lives in [docs/architecture.md](docs/architecture.md).

## Quick Start

### Nix-first development

```sh
nix develop
pg-start
eval "$(pg-env)"
mix setup
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

### Without Nix

Install:

- Elixir `1.18+`
- Erlang/OTP `27`
- PostgreSQL `18` or another modern PostgreSQL release
- Node.js `22+`

Then:

```sh
mix deps.get
mix assets.setup
mix ecto.setup
mix assets.build
mix phx.server
```

### Bootstrap admin

Public access is readonly by default. Set `HRAFNSYN_PUBLIC_READONLY=false` to require login, then bootstrap the first local admin with a username/password definition:

```sh
export HRAFNSYN_PUBLIC_READONLY=false
export HRAFNSYN_BOOTSTRAP_USERS_JSON='{"admin":{"password":"change-me-now","email":"admin@example.com","is_admin":true}}'
```

Configured bootstrap passwords are hashed on first boot and skipped for users that already exist.

## Runtime Model

Hrafnsyn does not use Oban for live feed polling. Each upstream source gets its own supervised GenServer, which means:

- independent failure/restart behavior per source
- per-source polling cadence
- easy support for multiple plane feeds and multiple vessel feeds
- clear reuse of the same ingest pipeline for future gRPC, replay, or app-native streaming

Track merging is deliberate:

- current state is unique on `(vehicle_type, identity)`
- history is logged per `(track_id, source_id, observed_at)`
- the latest observation wins for the merged track header
- source-specific historical points remain intact for replay and auditing

## Authentication Model

- anonymous users can view the live map in readonly mode when `public_readonly?` is enabled
- anonymous users are redirected to `/users/log-in` when `public_readonly?` is disabled
- login uses username + password, not email delivery
- the gRPC API issues JWT access tokens plus rotating refresh tokens
- users can revoke their own gRPC sessions and admins can revoke all gRPC sessions globally
- authenticated non-admin users are still readonly
- admins can create users from `/admin/users`
- logged-in users get a profile menu with password change and logout actions
- public signup is intentionally disabled

The future account/profile page is also where self-service token management should live in the web UI. The gRPC session APIs are already shaped to support that.

## Source Configuration

Sources can be overridden at runtime with `HRAFNSYN_SOURCES_JSON`.

Example:

```json
[
  {
    "id": "planes-main",
    "name": "Airplane SDR",
    "vehicle_type": "plane",
    "adapter": "dump1090",
    "base_url": "http://10.255.101.202",
    "poll_interval_ms": 1000,
    "enabled": true
  },
  {
    "id": "boats-main",
    "name": "Boat SDR",
    "vehicle_type": "vessel",
    "adapter": "ais_catcher",
    "base_url": "http://10.255.101.202:8100",
    "poll_interval_ms": 2500,
    "enabled": true
  }
]
```

The collector layer currently understands:

- `dump1090` via `/data/aircraft.json`
- `ais_catcher` via `/api/ships_array.json`

## Reverse Proxy

For NixOS deployments, the bundled module includes an opt-in `nginxHelper` modeled after the `vardrun` setup:

- websocket-aware HTTP proxying for Phoenix LiveView
- optional ACME-managed TLS
- optional content-type based gRPC passthrough for the gRPC listener when `grpc.enable = true`

Manual nginx examples for non-NixOS deployments live in [docs/deploy-generic-linux.md](docs/deploy-generic-linux.md).

## Observability

Hrafnsyn exposes Prometheus metrics at `/metrics` on the main endpoint, and can optionally run a separate metrics server when `METRICS_PORT` is set.

The bundled NixOS module supports:

- `metricsPort` for a dedicated scrape port
- `prometheus.enable` for automatic `services.prometheus.scrapeConfigs`
- `grafana.enable` for datasource + dashboard provisioning of the included Hrafnsyn overview dashboard

Spatial storage uses PostGIS geography points, which lets the detail panel and future APIs answer real distance questions without approximate float math.

## Documentation

- [Architecture](docs/architecture.md)
- [Development Guide](docs/development.md)
- [Deploy on NixOS](docs/deploy-nixos.md)
- [Deploy on Generic Linux](docs/deploy-generic-linux.md)

## Roadmap Hooks

- `Hrafnsyn.Ingest` remains the stable ingest seam for collectors and gRPC stream handlers alike.
- The gRPC auth/session API is designed so a future profile page can expose token self-management without reworking the backend contract.
- Track history is already durable enough to support richer playback, alerting, or export features without redesigning the storage model.
