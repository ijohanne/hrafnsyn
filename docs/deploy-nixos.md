# Deploy on NixOS

This guide covers the bundled NixOS module in [nix/module.nix](../nix/module.nix).
It matches the current runtime contract in `config/runtime.exs`.

## Flake Input

Add the repository as a flake input and import the module:

```nix
{
  inputs.hrafnsyn.url = "github:ijohanne/hrafnsyn";

  outputs = { self, nixpkgs, hrafnsyn, ... }: {
    nixosConfigurations.pakhet = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        hrafnsyn.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

## Minimal Service Configuration

```nix
{ pkgs, hrafnsyn, ... }:
{
  services.hrafnsyn = {
    enable = true;
    package = hrafnsyn.packages.${pkgs.system}.default;

    host = "tracks.example.com";
    listenAddress = "127.0.0.1";
    port = 4000;
    scheme = "https";
    externalPort = 443;
    autoMigrate = true;

    databaseUrlFile = /run/secrets/hrafnsyn-database-url;
    secretKeyBaseFile = /run/secrets/hrafnsyn-secret-key-base;
    sources = [
      {
        id = "planes-main";
        name = "Airplane SDR";
        vehicleType = "plane";
        adapter = "dump1090";
        baseUrl = "http://10.255.101.202";
        pollIntervalMs = 1000;
      }
      {
        id = "boats-main";
        name = "Boat SDR";
        vehicleType = "vessel";
        adapter = "ais_catcher";
        baseUrl = "http://10.255.101.202:8100";
        pollIntervalMs = 2500;
      }
    ];

    publicReadonly = false;

    users.admin = {
      password = "change-me-now";
      email = "admin@example.com";
      admin = true;
    };

    nginxHelper = {
      enable = true;
      domain = "tracks.example.com";
      enableACME = true;
    };
  };
}
```

This sets:

- `PHX_SERVER=true`
- `PORT`, `LISTEN_ADDRESS`, `PHX_HOST`
- `HRAFNSYN_SCHEME`, `HRAFNSYN_EXTERNAL_PORT`, `HRAFNSYN_TRUSTED_PROXIES`
- `HRAFNSYN_PUBLIC_READONLY`
- `HRAFNSYN_SOURCES_JSON` generated from `services.hrafnsyn.sources`
- `DATABASE_URL` and `SECRET_KEY_BASE` from systemd credentials

## Auth and Operator Modes

`services.hrafnsyn.publicReadonly` controls both the web dashboard and gRPC auth posture:

- `true`:
  - anonymous users can open the dashboard in readonly mode
  - `TrackingService` gRPC calls can be made without logging in
  - `TrackingIngress` accepts optional auth, which lets operators identify publishers without making auth mandatory
- `false`:
  - anonymous web users are redirected to `/users/log-in`
  - `TrackingService` requires JWT access tokens
  - `TrackingIngress` requires an authenticated admin token

The preferred way to bootstrap users is `services.hrafnsyn.users`:

```nix
services.hrafnsyn.users.ops = {
  password = "change-me-now";
  email = "ops@example.com";
  admin = true;
};
```

These passwords are only used on first boot for missing users. Hrafnsyn hashes them during startup
and leaves existing users unchanged.

The module also still exposes `bootstrapAdminEmail` and `bootstrapAdminPasswordHashFile` for the
legacy single-user bootstrap path, but new deployments should use `users` instead.

## Collector Sources

The preferred way to define collectors is `services.hrafnsyn.sources`:

```nix
services.hrafnsyn.sources = [
  {
    id = "planes-main";
    name = "Airplane SDR";
    vehicleType = "plane";
    adapter = "dump1090";
    baseUrl = "http://10.255.101.202";
    pollIntervalMs = 1000;
  }
  {
    id = "boats-main";
    name = "Boat SDR";
    vehicleType = "vessel";
    adapter = "ais_catcher";
    baseUrl = "http://10.255.101.202:8100";
    pollIntervalMs = 2500;
    enabled = true;
  }
];
```

The module converts that structured Nix data into the `HRAFNSYN_SOURCES_JSON`
runtime environment variable expected by the release.

`services.hrafnsyn.sourcesJsonFile` still works as a compatibility escape hatch,
but it is deprecated for normal use.

## Secret File Format

These module options expect raw file contents, not `KEY=value` shell snippets:

- `databaseUrlFile` -> only the Postgres URL
- `secretKeyBaseFile` -> only the secret key base
- `bootstrapAdminPasswordHashFile` -> only the bcrypt hash when using the legacy bootstrap path

If you still need `sourcesJsonFile`, the file should contain only the JSON array:

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

## gRPC

The gRPC listener is disabled unless `services.hrafnsyn.grpc.enable = true`.

```nix
{
  services.hrafnsyn.grpc = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 50051;
  };
}
```

When enabled, Hrafnsyn serves:

- `AuthService`
- `TrackingService`
- `TrackingIngress`

The web app also exposes:

- `/grpc` for a browsable contract page
- `/grpc/tracking.proto` for the checked-in protobuf contract

JWT signing defaults to `SECRET_KEY_BASE`. If you want a separate signing secret or custom token TTLs,
set them through `services.hrafnsyn.extraEnv`:

```nix
{
  services.hrafnsyn.extraEnv = {
    HRAFNSYN_JWT_SIGNING_SECRET = "replace-me";
    HRAFNSYN_JWT_ACCESS_TTL_SECONDS = "900";
    HRAFNSYN_JWT_REFRESH_TTL_SECONDS = "2592000";
  };
}
```

## nginx Helper

The optional nginx helper keeps Phoenix/LiveView and gRPC on one external URL.

```nix
{
  services.hrafnsyn.nginxHelper = {
    enable = true;
    domain = "tracks.example.com";
    enableACME = true;
    # acmeServer = "https://acme-staging-v02.api.letsencrypt.org/directory";
  };
}
```

When `grpc.enable = true`, the helper routes requests with `Content-Type: application/grpc`
to the gRPC upstream and everything else to Phoenix. If you prefer to manage nginx yourself,
leave `nginxHelper.enable = false`.

`trustedProxies` controls which upstream proxy IP ranges are trusted for forwarded host, port,
and scheme headers. The default trusts loopback only.

## Metrics, Prometheus, and Grafana

The main Phoenix endpoint always serves `/metrics`. If you want a dedicated metrics listener,
set `metricsPort`:

```nix
{
  services.hrafnsyn = {
    metricsPort = 9568;

    prometheus = {
      enable = true;
      scrapeInterval = "15s";
    };

    grafana = {
      enable = true;
      prometheusUrl = "http://127.0.0.1:9090";
      datasourceName = "Hrafnsyn";
      datasourceUid = "hrafnsyn-prometheus";
    };
  };
}
```

What this does:

- `metricsPort` exposes PromEx on a dedicated port
- `prometheus.enable` appends a scrape job to `services.prometheus.scrapeConfigs`
- `grafana.enable` provisions a Prometheus datasource and the bundled overview dashboard

If `metricsPort = null`, Prometheus should scrape the main web port instead.

## PostgreSQL

Point `databaseUrlFile` at any reachable PostgreSQL instance. Example raw file contents:

```text
ecto://hrafnsyn:supersecret@pakhet.example.internal:5432/hrafnsyn
```

The current schema expects these extensions in the target database:

- `citext`
- `pg_trgm`
- `postgis`

If PostgreSQL runs locally on NixOS, enable PostGIS there too:

```nix
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    extensions = ps: [ ps.postgis ];
  };
}
```
