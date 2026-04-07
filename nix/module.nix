{ config, lib, pkgs, ... }:
let
  cfg = config.services.hrafnsyn;
  nginxEnabled = cfg.nginxHelper.enable;
  grafanaDashboardPath = pkgs.runCommand "hrafnsyn-grafana-dashboards" { } ''
    mkdir -p "$out"
    cp ${../grafana/dashboards/hrafnsyn-overview.json} "$out/hrafnsyn-overview.json"
  '';
in
{
  options.services.hrafnsyn = {
    enable = lib.mkEnableOption "Hrafnsyn unified tracking service";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The Hrafnsyn release package to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hrafnsyn";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "hrafnsyn";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
    };

    metricsPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    externalPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
    };

    scheme = lib.mkOption {
      type = lib.types.enum [ "http" "https" ];
      default = "https";
    };

    trustedProxies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1/8" "::1/128" ];
    };

    databaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    databaseUrlFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };

    secretKeyBaseFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a raw file containing the SECRET_KEY_BASE value.";
    };

    bootstrapAdminEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    bootstrapAdminPasswordHashFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a raw file containing the bcrypt hash for the bootstrap admin.";
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          password = lib.mkOption {
            type = lib.types.str;
            description = "Initial plaintext password to hash on first boot only.";
          };

          email = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };

          admin = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
      }));
      default = { };
      description = ''
        Bootstrap users to provision at startup. Attribute names are usernames.
        Existing users are left unchanged.
      '';
    };

    mapStyleUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://tiles.openfreemap.org/styles/liberty";
    };

    sourcesJsonFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a raw JSON file describing configured collectors.";
    };

    publicReadonly = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    autoMigrate = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    prometheus = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      scrapeInterval = lib.mkOption {
        type = lib.types.str;
        default = "15s";
      };
    };

    grafana = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      datasourceName = lib.mkOption {
        type = lib.types.str;
        default = "Hrafnsyn";
      };

      datasourceUid = lib.mkOption {
        type = lib.types.str;
        default = "hrafnsyn-prometheus";
      };

      prometheusUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:9090";
      };

      dashboardProviderName = lib.mkOption {
        type = lib.types.str;
        default = "hrafnsyn";
      };
    };

    grpc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 50051;
      };
    };

    nginxHelper = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable an nginx vhost that keeps Phoenix and gRPC on one external URL.
          Requests with `Content-Type: application/grpc` are forwarded to the
          gRPC listener and everything else is proxied to Phoenix/LiveView.
        '';
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = cfg.host;
      };

      enableACME = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      acmeServer = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.databaseUrl != null || cfg.databaseUrlFile != null;
        message = "services.hrafnsyn.databaseUrl or databaseUrlFile must be configured.";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    users.groups.${cfg.group} = {};

    systemd.services.hrafnsyn = {
      description = "Hrafnsyn unified tracking";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      wants = [ "network.target" ];

      environment =
        {
          PHX_SERVER = "true";
          PORT = builtins.toString cfg.port;
          LISTEN_ADDRESS = cfg.listenAddress;
          PHX_HOST = cfg.host;
          HRAFNSYN_SCHEME = cfg.scheme;
          HRAFNSYN_EXTERNAL_PORT = builtins.toString cfg.externalPort;
          HRAFNSYN_TRUSTED_PROXIES = builtins.concatStringsSep "," cfg.trustedProxies;
          HRAFNSYN_MAP_STYLE_URL = cfg.mapStyleUrl;
          HRAFNSYN_PUBLIC_READONLY = if cfg.publicReadonly then "true" else "false";
        }
        // lib.optionalAttrs (cfg.databaseUrl != null) { DATABASE_URL = cfg.databaseUrl; }
        // lib.optionalAttrs (cfg.metricsPort != null) {
          METRICS_PORT = builtins.toString cfg.metricsPort;
        }
        // lib.optionalAttrs cfg.grpc.enable {
          GRPC_PORT = builtins.toString cfg.grpc.port;
          GRPC_LISTEN_ADDRESS = cfg.grpc.listenAddress;
        }
        // lib.optionalAttrs (cfg.bootstrapAdminEmail != null) {
          BOOTSTRAP_ADMIN_EMAIL = cfg.bootstrapAdminEmail;
        }
        // lib.optionalAttrs (cfg.users != { }) {
          HRAFNSYN_BOOTSTRAP_USERS_JSON =
            builtins.toJSON
              (lib.mapAttrs
                (_username: user: {
                  password = user.password;
                  email = user.email;
                  is_admin = user.admin;
                })
                cfg.users);
        }
        // cfg.extraEnv;

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "/var/lib/${cfg.user}";
        Restart = "on-failure";
        StateDirectory = cfg.user;
        RuntimeDirectory = cfg.user;
        LoadCredential =
          lib.filter (value: value != null) [
            "secret_key_base:${cfg.secretKeyBaseFile}"
            (if cfg.databaseUrlFile != null then "database_url:${cfg.databaseUrlFile}" else null)
            (if cfg.bootstrapAdminPasswordHashFile != null then "bootstrap_admin_password_hash:${cfg.bootstrapAdminPasswordHashFile}" else null)
            (if cfg.sourcesJsonFile != null then "sources_json:${cfg.sourcesJsonFile}" else null)
          ];
      };

      script = ''
        export SECRET_KEY_BASE="$(< "$CREDENTIALS_DIRECTORY/secret_key_base")"

        ${lib.optionalString (cfg.databaseUrlFile != null) ''
          export DATABASE_URL="$(< "$CREDENTIALS_DIRECTORY/database_url")"
        ''}

        ${lib.optionalString (cfg.bootstrapAdminPasswordHashFile != null) ''
          export BOOTSTRAP_ADMIN_PASSWORD_HASH="$(< "$CREDENTIALS_DIRECTORY/bootstrap_admin_password_hash")"
        ''}

        ${lib.optionalString (cfg.sourcesJsonFile != null) ''
          export HRAFNSYN_SOURCES_JSON="$(< "$CREDENTIALS_DIRECTORY/sources_json")"
        ''}

        ${lib.optionalString cfg.autoMigrate ''
          ${cfg.package}/bin/hrafnsyn eval 'Hrafnsyn.Release.migrate()'
        ''}

        exec ${cfg.package}/bin/hrafnsyn start
      '';
    };

    services.nginx = lib.mkIf nginxEnabled {
      enable = true;
      virtualHosts.${cfg.nginxHelper.domain} =
        {
          forceSSL = cfg.nginxHelper.enableACME;
          enableACME = cfg.nginxHelper.enableACME;
          locations."~ ^/" = {
            proxyPass = "http://${cfg.listenAddress}:${builtins.toString cfg.port}";
            proxyWebsockets = true;
            extraConfig =
              ''
                # Keep HTTP/WebSocket and gRPC traffic on a single clean URL,
                # matching the vardrun routing pattern.
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              ''
              + lib.optionalString cfg.grpc.enable ''
                grpc_read_timeout 1h;
                grpc_send_timeout 1h;
                grpc_set_header X-Real-IP $remote_addr;
                grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

                if ($http_content_type ~* "application/grpc") {
                  grpc_pass grpc://${cfg.grpc.listenAddress}:${builtins.toString cfg.grpc.port};
                }
              '';
          };
        }
        // lib.optionalAttrs (cfg.nginxHelper.acmeServer != null) {
          acmeServer = cfg.nginxHelper.acmeServer;
        };
    };

    services.prometheus.scrapeConfigs = lib.mkIf cfg.prometheus.enable [
      {
        job_name = "hrafnsyn";
        scrape_interval = cfg.prometheus.scrapeInterval;
        metrics_path = "/metrics";
        static_configs = [
          {
            targets = [
              "${cfg.listenAddress}:${builtins.toString (if cfg.metricsPort != null then cfg.metricsPort else cfg.port)}"
            ];
            labels = { instance = cfg.host; };
          }
        ];
      }
    ];

    services.grafana = lib.mkIf cfg.grafana.enable {
      enable = true;
      provision.enable = true;
      provision.datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = cfg.grafana.datasourceName;
            uid = cfg.grafana.datasourceUid;
            type = "prometheus";
            access = "proxy";
            url = cfg.grafana.prometheusUrl;
            editable = false;
            isDefault = true;
          }
        ];
      };
      provision.dashboards.settings.providers = [
        {
          name = cfg.grafana.dashboardProviderName;
          options.path = grafanaDashboardPath;
        }
      ];
    };
  };
}
