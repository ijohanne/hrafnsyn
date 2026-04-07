# Deploy on Generic Linux

## Requirements

Install:

- Erlang/OTP `27`
- Elixir `1.18+`
- PostgreSQL `18` or similar
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

The release ends up under:

```text
_build/prod/rel/hrafnsyn
```

## Environment

Create `/etc/hrafnsyn.env`:

```sh
PHX_SERVER=true
PHX_HOST=tracks.example.com
LISTEN_ADDRESS=127.0.0.1
PORT=4000
METRICS_PORT=9568
HRAFNSYN_SCHEME=https
HRAFNSYN_EXTERNAL_PORT=443
HRAFNSYN_TRUSTED_PROXIES=127.0.0.1/8,::1/128
DATABASE_URL=ecto://hrafnsyn:replace-me@127.0.0.1:5432/hrafnsyn
SECRET_KEY_BASE=replace-with-mix-phx-gen-secret
BOOTSTRAP_ADMIN_EMAIL=admin@example.com
BOOTSTRAP_ADMIN_PASSWORD_HASH=$2b$12$replace-me
HRAFNSYN_PUBLIC_READONLY=true
HRAFNSYN_MAP_STYLE_URL=https://tiles.openfreemap.org/styles/liberty
HRAFNSYN_SOURCES_JSON=[{"id":"planes-main","name":"Airplane SDR","vehicle_type":"plane","adapter":"dump1090","base_url":"http://10.255.101.202","poll_interval_ms":1000,"enabled":true},{"id":"boats-main","name":"Boat SDR","vehicle_type":"vessel","adapter":"ais_catcher","base_url":"http://10.255.101.202:8100","poll_interval_ms":2500,"enabled":true}]
```

Generate a secret key with:

```sh
mix phx.gen.secret
```

Generate the admin password hash with:

```sh
mix run -e 'IO.puts(Bcrypt.hash_pwd_salt("change-me-now"))'
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
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

If you are not exposing a gRPC listener yet, remove the `grpc_*` lines and the conditional `grpc_pass` block.

For ACME-managed TLS, pair the server block with your preferred certbot/acme.sh/lego flow, or use distro-native nginx ACME integration where available. The app-side environment contract above already supports running behind HTTPS on an external `443` while binding Phoenix locally.

## Prometheus and Grafana

If you want Prometheus to scrape a dedicated metrics listener, keep `METRICS_PORT` set and add a job like:

```yaml
- job_name: hrafnsyn
  scrape_interval: 15s
  metrics_path: /metrics
  static_configs:
    - targets:
        - 127.0.0.1:9568
```

The repository also ships a Grafana dashboard at:

```text
grafana/dashboards/hrafnsyn-overview.json
```

You can import it manually into Grafana or provision it with your existing deployment tooling. If you do not need a separate scrape port, you can omit `METRICS_PORT` and scrape `http://127.0.0.1:4000/metrics` instead.

## Nix-built Release on Non-NixOS

If you prefer a Nix-built artifact but are deploying to another Linux host, you can build the release with:

```sh
nix build .#default
```

Then copy the resulting release bundle to the target machine and run it under systemd with the same environment contract shown above.
