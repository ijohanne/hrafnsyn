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
{ pkgs, hrafnsyn, ... }:
{
  services.hrafnsyn = {
    enable = true;
    package = hrafnsyn.packages.${pkgs.system}.default;

    host = "tracks.example.com";
    port = 4000;
    autoMigrate = true;

    databaseUrlFile = /run/secrets/hrafnsyn-database-url;
    secretKeyBaseFile = /run/secrets/hrafnsyn-secret-key-base;

    bootstrapAdminEmail = "admin@example.com";
    bootstrapAdminPasswordHashFile = /run/secrets/hrafnsyn-admin-password-hash;

    sourcesJsonFile = /run/secrets/hrafnsyn-sources.json;
  };
}
```

## Secret File Format

These module options expect raw file contents, not `KEY=value` shell snippets:

- `databaseUrlFile` -> only the Postgres URL
- `secretKeyBaseFile` -> only the secret key base
- `bootstrapAdminPasswordHashFile` -> only the bcrypt hash
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

## Password Hash Generation

Generate a bcrypt hash from the dev shell:

```sh
nix develop -c mix run -e 'IO.puts(Bcrypt.hash_pwd_salt("change-me-now"))'
```

## Reverse Proxy

The module does not force nginx policy. A minimal nginx vhost looks like:

```nix
{
  services.nginx.virtualHosts."tracks.example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:4000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Host $host;
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

PostgreSQL 18 works fine with the current schema and extensions (`citext`, `pg_trgm`).
