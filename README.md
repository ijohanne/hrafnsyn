<p align="center">
  <img src="priv/static/images/logo.svg" alt="Hrafnsyn" width="132">
</p>

<h1 align="center">Hrafnsyn</h1>

<p align="center">
  Unified aircraft and vessel tracking with Phoenix LiveView, PostgreSQL/PostGIS,
  realtime updates, durable history, and an optional gRPC surface.
</p>

## Overview

Hrafnsyn merges ADS-B aircraft data and AIS vessel data into one operational map with:

- realtime LiveView updates backed by PubSub
- durable current-state and route-history storage in PostgreSQL/PostGIS
- multi-source collection, merging, search, and replay-friendly history
- readonly public mode by default, with lightweight admin-managed users when needed
- an optional gRPC listener for auth, track reads, live updates, and ingestion

The core ingest boundary is `Hrafnsyn.Ingest`, so HTTP collectors and future publishers
reuse the same normalization and persistence path.

## Quick Start

### Recommended local workflow

If you are using the Nix dev shell, the shortest path is:

```sh
nix develop
app
```

`app` resets the local Postgres cluster, starts it, runs `mix ecto.setup`, and boots Phoenix.

Visit [http://localhost:4000](http://localhost:4000).

### Manual local workflow

If you want the steps individually:

```sh
nix develop
pg-start
eval "$(pg-env)"
mix setup
mix phx.server
```

Without Nix, install Elixir `1.18+`, Erlang/OTP `27`, PostgreSQL `18` or another modern
PostgreSQL release with PostGIS, and Node.js `22+`, then follow the development guide below.

### Local auth bootstrap

Public mode is readonly by default. To require login locally and create the first admin on boot:

```sh
export HRAFNSYN_PUBLIC_READONLY=false
export HRAFNSYN_BOOTSTRAP_USERS_JSON='{"admin":{"password":"change-me-now","email":"admin@example.com","is_admin":true}}'
```

Bootstrap passwords are hashed on first boot and skipped for users that already exist.

## Runtime Snapshot

- Collectors: one supervised GenServer per configured upstream source
- Storage: merged live tracks plus append-only historical points in Postgres
- Auth:
  - `HRAFNSYN_PUBLIC_READONLY=true` keeps the web UI readable without login
  - `HRAFNSYN_PUBLIC_READONLY=false` requires login for the dashboard and JWTs for tracking gRPC calls
  - authenticated non-admin users remain readonly
- gRPC:
  - disabled unless `GRPC_PORT` is set
  - serves `AuthService`, `TrackingService`, and `TrackingIngress`
  - publishes a browsable contract page at `/grpc` and the checked-in proto at `/grpc/tracking.proto`
- Metrics:
  - `/metrics` is always available on the main endpoint
  - `METRICS_PORT` can expose a dedicated scrape listener

Runtime source configuration is driven by `HRAFNSYN_SOURCES_JSON`, while the dev environment
also supports `HRAFNSYN_PLANE_URL` and `HRAFNSYN_BOAT_URL` overrides for the default two-source setup.

## Deployment

Two deployment paths are documented and kept in sync with `config/runtime.exs` and `nix/module.nix`:

- [Deploy on NixOS](docs/deploy-nixos.md)
- [Deploy on Generic Linux](docs/deploy-generic-linux.md)

Both guides cover:

- runtime environment and bind addresses
- public readonly versus authenticated/private operation
- bootstrap users and first-admin setup
- optional gRPC exposure and JWT configuration
- metrics, Prometheus, and Grafana wiring

## Documentation

- [Architecture](docs/architecture.md)
- [Development Guide](docs/development.md)
- [Deploy on NixOS](docs/deploy-nixos.md)
- [Deploy on Generic Linux](docs/deploy-generic-linux.md)
