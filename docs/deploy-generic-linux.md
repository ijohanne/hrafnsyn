# Deploy on Generic Linux

This guide is for release deployments outside the bundled NixOS module. It matches the
runtime contract in `config/runtime.exs`.

## Requirements

Install:

- Erlang/OTP `27`
- Elixir `1.18+`
- PostgreSQL `18` or another recent PostgreSQL release with PostGIS
- Node.js `22+`
- `git`, `make`, and a build toolchain for native deps

## Database

Create a database and role:

```sql
CREATE ROLE hrafnsyn LOGIN PASSWORD 'replace-me';
CREATE DATABASE hrafnsyn OWNER hrafnsyn;
```

Enable the required extensions in the target database:

```sql
\c hrafnsyn
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS postgis;
```

## Build a Release

```sh
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

The release bundle ends up under:

```text
_build/prod/rel/hrafnsyn
```

## Environment File

Create `/etc/hrafnsyn.env`:

```sh
PHX_SERVER=true
PHX_HOST=tracks.example.com
LISTEN_ADDRESS=127.0.0.1
PORT=4000

HRAFNSYN_SCHEME=https
HRAFNSYN_EXTERNAL_PORT=443
HRAFNSYN_TRUSTED_PROXIES=127.0.0.1/8,::1/128

# Either a full URL:
DATABASE_URL=ecto://hrafnsyn:replace-me@127.0.0.1:5432/hrafnsyn

# Or structured settings:
# DATABASE_HOST=/run/postgresql
# DATABASE_NAME=hrafnsyn
# DATABASE_USER=hrafnsyn
# DATABASE_PASSWORD=replace-me

SECRET_KEY_BASE=replace-with-mix-phx-gen-secret

HRAFNSYN_PUBLIC_READONLY=false
HRAFNSYN_BOOTSTRAP_USERS_JSON='{"admin":{"password":"change-me-now","email":"admin@example.com","is_admin":true}}'

HRAFNSYN_MAP_STYLE_URL=https://tiles.openfreemap.org/styles/liberty
HRAFNSYN_SOURCES_JSON=[{"id":"planes-main","name":"Airplane SDR","vehicle_type":"plane","adapter":"dump1090","base_url":"http://10.255.101.202","poll_interval_ms":1000,"enabled":true},{"id":"boats-main","name":"Boat SDR","vehicle_type":"vessel","adapter":"ais_catcher","base_url":"http://10.255.101.202:8100","poll_interval_ms":2500,"enabled":true}]
# Optional static aircraft enrichment artifact
# HRAFNSYN_AIRCRAFT_DB_PATH=/opt/hrafnsyn/share/aircraft-db.ndjson

METRICS_PORT=9568

GRPC_PORT=50051
GRPC_LISTEN_ADDRESS=127.0.0.1
HRAFNSYN_JWT_ACCESS_TTL_SECONDS=900
HRAFNSYN_JWT_REFRESH_TTL_SECONDS=2592000
# Optional; defaults to SECRET_KEY_BASE when unset
# HRAFNSYN_JWT_SIGNING_SECRET=replace-with-separate-jwt-secret
```

Generate a secret key with:

```sh
mix phx.gen.secret
```

### Required settings

- `PHX_SERVER=true`
- `PHX_HOST`
- either `DATABASE_URL` or `DATABASE_HOST` + `DATABASE_NAME` + `DATABASE_USER`
- `SECRET_KEY_BASE`

### Common operator settings

- `LISTEN_ADDRESS` and `PORT` control the Phoenix bind address
- `HRAFNSYN_SCHEME`, `HRAFNSYN_EXTERNAL_PORT`, and `HRAFNSYN_TRUSTED_PROXIES` keep URL generation, secure-cookie handling, and proxy header rewriting correct behind nginx
- `DATABASE_HOST`, `DATABASE_NAME`, `DATABASE_USER`, and optional `DATABASE_PASSWORD` provide the same structured DB contract as the NixOS module
- `HRAFNSYN_PUBLIC_READONLY` controls whether anonymous access is allowed
- `HRAFNSYN_BOOTSTRAP_USERS_JSON` is the preferred first-user bootstrap path
- `HRAFNSYN_SOURCES_JSON` defines the live collectors
- `HRAFNSYN_AIRCRAFT_DB_PATH` optionally enables static aircraft enrichment
- `METRICS_PORT` is optional; omit it to keep metrics on the main web port

Legacy single-user bootstrap environment variables are still supported for compatibility:

- `BOOTSTRAP_ADMIN_USERNAME`
- `BOOTSTRAP_ADMIN_EMAIL`
- `BOOTSTRAP_ADMIN_PASSWORD`
- `BOOTSTRAP_ADMIN_PASSWORD_HASH`

New deployments should prefer `HRAFNSYN_BOOTSTRAP_USERS_JSON`.

## Auth and Operator Modes

`HRAFNSYN_PUBLIC_READONLY` controls both the web UI and the gRPC auth posture:

- `true`:
  - anonymous users can open the dashboard in readonly mode
  - `TrackingService` gRPC calls can be made without login
  - `TrackingIngress` accepts optional auth
- `false`:
  - anonymous web users are redirected to `/users/log-in`
  - `TrackingService` requires JWT access tokens
  - `TrackingIngress` requires an authenticated admin token

Authenticated non-admin users remain readonly in the web app and gRPC auth model.

Bootstrap passwords are hashed on first start and skipped for users that already exist.

If you want the static aircraft DB on a generic Linux deployment, generate it ahead of time with:

```sh
nix build .#aircraft-db
install -Dm0644 result/share/hrafnsyn/aircraft-db.ndjson /opt/hrafnsyn/share/aircraft-db.ndjson
```

## Migrate

Run migrations once before first start:

```sh
_build/prod/rel/hrafnsyn/bin/hrafnsyn eval 'Hrafnsyn.Release.migrate()'
```

## systemd Unit

Create `/etc/systemd/system/hrafnsyn.service`:

```ini
[Unit]
Description=Hrafnsyn unified tracking
After=network.target

[Service]
User=hrafnsyn
Group=hrafnsyn
WorkingDirectory=/opt/hrafnsyn
EnvironmentFile=/etc/hrafnsyn.env
ExecStart=/opt/hrafnsyn/bin/hrafnsyn start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Then:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now hrafnsyn
```

## Reverse Proxy

Example nginx site:

```nginx
server {
  server_name tracks.example.com;

  location / {
    grpc_read_timeout 1h;
    grpc_send_timeout 1h;
    grpc_set_header X-Real-IP $remote_addr;
    grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    if ($http_content_type ~* "application/grpc") {
      grpc_pass grpc://127.0.0.1:50051;
    }

    proxy_pass http://127.0.0.1:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

This keeps Phoenix/LiveView and gRPC on one public URL. If you are not exposing the gRPC listener,
remove the `grpc_*` lines and the conditional `grpc_pass` block.

When gRPC is enabled, Hrafnsyn serves:

- `AuthService`
- `TrackingService`
- `TrackingIngress`

The web app also publishes:

- `/grpc` for a browsable contract page
- `/grpc/tracking.proto` for the checked-in protobuf contract

For ACME-managed TLS, pair this with your preferred certbot, acme.sh, lego, or distro-native
ACME flow.

## Prometheus and Grafana

If you set `METRICS_PORT`, Prometheus can scrape that dedicated listener:

```yaml
- job_name: hrafnsyn
  scrape_interval: 15s
  metrics_path: /metrics
  static_configs:
    - targets:
        - 127.0.0.1:9568
```

If you omit `METRICS_PORT`, scrape the main Phoenix port instead.

The repository also ships a Grafana dashboard at:

```text
grafana/dashboards/hrafnsyn-overview.json
```

Import it manually or provision it with your existing Grafana tooling.

## Nix-built Release on Non-NixOS

If you prefer a Nix-built artifact but are deploying to another Linux host, build with:

```sh
nix build .#default
```

Then copy the resulting release bundle to the target machine and run it under systemd with the
same environment contract shown above.
