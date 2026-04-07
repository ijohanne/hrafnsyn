# Deploy on NixOS

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
{ pkgs, config, hrafnsyn, ... }:
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
    publicReadonly = false;

    users.admin = {
      password = config.sops.placeholder.hrafnsyn-admin-password;
      email = "admin@example.com";
      admin = true;
    };

    sourcesJsonFile = /run/secrets/hrafnsyn-sources.json;

    nginxHelper = {
      enable = true;
      domain = "tracks.example.com";
      enableACME = true;
    };
  };
}
```

## Secret File Format

These module options expect raw file contents, not `KEY=value` shell snippets:

- `databaseUrlFile` -> only the Postgres URL
- `secretKeyBaseFile` -> only the secret key base
- `sourcesJsonFile` -> only the JSON array

## Example Source JSON

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

Bootstrap user passwords are hashed by Hrafnsyn during startup and skipped once the user already exists.

## Opt-in nginx Helper

The module now has an optional nginx helper that mirrors the `vardrun` approach:

- plain HTTP proxying to the Phoenix endpoint
- websocket forwarding for LiveView
- optional ACME certificate handling
- optional content-type based gRPC passthrough for a future gRPC listener

Example with built-in nginx + ACME:

```nix
{
  services.hrafnsyn = {
    enable = true;
    package = hrafnsyn.packages.${pkgs.system}.default;
    host = "tracks.example.com";
    listenAddress = "127.0.0.1";
    port = 4000;
    databaseUrlFile = /run/secrets/hrafnsyn-database-url;
    secretKeyBaseFile = /run/secrets/hrafnsyn-secret-key-base;

    nginxHelper = {
      enable = true;
      domain = "tracks.example.com";
      enableACME = true;
      # acmeServer = "https://acme-staging-v02.api.letsencrypt.org/directory";
    };
  };
}
```

If you want nginx provisioning but not automatic certificate management, leave `enableACME = false`.

If you want to prepare nginx for future gRPC ingress too:

```nix
{
  services.hrafnsyn.grpc = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 50051;
  };
}
```

When `grpc.enable = true`, the helper adds conditional `grpc_pass` routing for requests whose `Content-Type` matches `application/grpc`.

## Metrics, Scraping, and Dashboards

The NixOS module can also wire observability in the same opt-in style:

```nix
{
  services.hrafnsyn = {
    enable = true;
    package = hrafnsyn.packages.${pkgs.system}.default;
    host = "tracks.example.com";
    listenAddress = "127.0.0.1";
    port = 4000;
    metricsPort = 9568;

    databaseUrlFile = /run/secrets/hrafnsyn-database-url;
    secretKeyBaseFile = /run/secrets/hrafnsyn-secret-key-base;

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

- `metricsPort` enables a dedicated PromEx metrics server on that port
- `prometheus.enable` appends a scrape job to `services.prometheus.scrapeConfigs`
- `grafana.enable` provisions:
  - a Prometheus datasource
  - the bundled `Hrafnsyn Overview` dashboard from `grafana/dashboards/hrafnsyn-overview.json`

If you already manage Grafana elsewhere, leave `grafana.enable = false` and import the dashboard JSON manually.

## Manual nginx

If you do not want the helper, you can still manage nginx yourself:

```nix
{
  services.nginx.virtualHosts."tracks.example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:4000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}
```

## PostgreSQL

For Pakhet or another existing Postgres service, point `databaseUrlFile` at the remote URL. Example:

```text
ecto://hrafnsyn:supersecret@pakhet.example.internal:5432/hrafnsyn
```

PostgreSQL 18 works fine with the current schema and extensions (`citext`, `pg_trgm`, `postgis`).

If you run PostgreSQL locally on NixOS, enable PostGIS in the PostgreSQL service too:

```nix
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    extensions = ps: [ ps.postgis ];
  };
}
```
