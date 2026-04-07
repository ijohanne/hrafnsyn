{ config, lib, pkgs, ... }:
let
  cfg = config.services.hrafnsyn;
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

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
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
          PHX_HOST = cfg.host;
          HRAFNSYN_MAP_STYLE_URL = cfg.mapStyleUrl;
          HRAFNSYN_PUBLIC_READONLY = if cfg.publicReadonly then "true" else "false";
        }
        // lib.optionalAttrs (cfg.databaseUrl != null) { DATABASE_URL = cfg.databaseUrl; }
        // lib.optionalAttrs (cfg.bootstrapAdminEmail != null) {
          BOOTSTRAP_ADMIN_EMAIL = cfg.bootstrapAdminEmail;
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
  };
}
