# Development

## Prerequisites

The easiest path is Nix with flakes enabled.

## Nix Dev Shell

```sh
nix develop
```

The shell provides:

- Elixir `1.18`
- Erlang/OTP `27`
- PostgreSQL `18`
- Node.js `22`
- `esbuild`
- Tailwind CSS v4
- helper scripts for a local Postgres cluster

## Fastest Local Start

Inside the dev shell, the shortest path is:

```sh
app
```

That resets the local Postgres cluster, starts it, runs `mix ecto.setup`, and boots Phoenix.

## Local Postgres Helpers

The dev shell ships with a persistent local cluster under `.pgdev/`.

Start it:

```sh
pg-start
eval "$(pg-env)"
```

Useful commands:

```sh
pg-status
pg-isready
pg-stop
pg-reset
```

This exports:

- `DATABASE_URL` for `hrafnsyn_dev`
- `TEST_DATABASE_URL` for `hrafnsyn_test`

## First Boot

```sh
mix setup
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000).

## Tests and Quality Gates

```sh
mix test
mix credo --strict
mix precommit
```

`mix precommit` runs:

- compile with warnings as errors
- remove unused unlocked deps
- formatter
- Credo strict
- tests

## Source Overrides

For quick local experiments you can override the default source URLs:

```sh
export HRAFNSYN_PLANE_URL="http://10.255.101.202"
export HRAFNSYN_BOAT_URL="http://10.255.101.202:8100"
```

For full multi-source runtime configuration, use `HRAFNSYN_SOURCES_JSON`:

```sh
export HRAFNSYN_SOURCES_JSON='[
  {"id":"planes-main","name":"Airplane SDR","vehicle_type":"plane","adapter":"dump1090","base_url":"http://10.255.101.202","poll_interval_ms":1000,"enabled":true},
  {"id":"planes-backup","name":"Airplane SDR Backup","vehicle_type":"plane","adapter":"dump1090","base_url":"http://10.255.101.203","poll_interval_ms":1500,"enabled":true},
  {"id":"boats-main","name":"Boat SDR","vehicle_type":"vessel","adapter":"ais_catcher","base_url":"http://10.255.101.202:8100","poll_interval_ms":2500,"enabled":true}
]'
```

## Local Auth Testing

The runtime switch for anonymous readonly mode is `HRAFNSYN_PUBLIC_READONLY`. Set it to `false`
to require login locally.

The repository includes a safe local example at `.env.example`:

```sh
cp .env.example .env.local
direnv reload
```

The repo `.envrc` loads `.env` and `.env.local` through `direnv`, which exports those values into the dev shell.

The example config boots a local admin user with username/password auth:

- username: `admin`
- password: `change-me-now`

Bootstrap user passwords must be at least 12 characters long. If you use a shorter password, the
bootstrap user will not be created and login will fail.

Run the app after sourcing the file:

```sh
app
```

Then sign in at [http://localhost:4000/users/log-in](http://localhost:4000/users/log-in) to test
login and admin flows.

Bootstrap passwords are hashed during startup and ignored for users that already exist. If you are
using the manual Postgres helpers and need to replay the bootstrap flow, run `pg-reset` first so
the local user table starts clean.

## Assets

```sh
mix assets.build
mix assets.deploy
```

MapLibre is vendored into `priv/static/vendor/` so builds do not depend on CDN fetches.

## Proto Contract

The current gRPC contract lives at:

```text
proto/hrafnsyn/v1/tracking.proto
```

The Elixir protobuf/service modules are checked into `lib/hrafnsyn/grpc/v1/` so the app can compile without `protoc` in the dev shell. Runtime gRPC settings are controlled by:

- `GRPC_PORT` and `GRPC_LISTEN_ADDRESS`
- `HRAFNSYN_JWT_ACCESS_TTL_SECONDS`
- `HRAFNSYN_JWT_REFRESH_TTL_SECONDS`
- `HRAFNSYN_JWT_SIGNING_SECRET` (defaults to `SECRET_KEY_BASE` when unset)
