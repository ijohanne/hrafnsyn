{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        esbuild = pkgs.esbuild;
        tailwindcss = pkgs.tailwindcss_4;
        beamPackages = pkgs.beam.packages.erlang_27;
        postgres = pkgs.postgresql_18.withPackages (ps: [ ps.postgis ]);

        heroiconsSrc = pkgs.fetchFromGitHub {
          owner = "tailwindlabs";
          repo = "heroicons";
          rev = "v2.2.0";
          hash = "sha256-Jcxr1fSbmXO9bZKeg39Z/zVN0YJp17TX3LH5Us4lsZU=";
        };

        pg-dev-core = pkgs.writeShellScriptBin "pg-dev-core" ''
          set -euo pipefail

          PGBIN="${postgres}/bin"
          BASE_DIR="''${PGDEV_DIR:-$PWD/.pgdev}"
          DATA_DIR="$BASE_DIR/data"
          RUN_DIR="$BASE_DIR/run"
          LOG_FILE="$BASE_DIR/postgres.log"
          PORT_FILE="$BASE_DIR/port"

          ensure_dirs() {
            mkdir -p "$BASE_DIR" "$RUN_DIR"
          }

          choose_port() {
            if [ -f "$PORT_FILE" ]; then
              cat "$PORT_FILE"
              return 0
            fi

            local port=""
            for _ in $(seq 1 80); do
              local candidate=$(( (RANDOM % 16384) + 49152 ))
              if ! "$PGBIN/pg_isready" -q -h 127.0.0.1 -p "$candidate" >/dev/null 2>&1; then
                port="$candidate"
                break
              fi
            done

            if [ -z "$port" ]; then
              echo "Failed to choose a free random Postgres port." >&2
              exit 1
            fi

            printf "%s" "$port" > "$PORT_FILE"
            printf "%s" "$port"
          }

          read_port() {
            if [ -f "$PORT_FILE" ]; then
              cat "$PORT_FILE"
              return 0
            fi

            echo "No port assigned yet. Run pg-init first." >&2
            exit 1
          }

          db_url() {
            local dbname="$1"
            local port
            port="$(read_port)"
            printf "ecto://%s@localhost:%s/%s?socket_dir=%s" "$(whoami)" "$port" "$dbname" "$RUN_DIR"
          }

          cmd_init() {
            ensure_dirs

            if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
              echo "Initializing Postgres cluster at $DATA_DIR"
              rm -rf "$DATA_DIR"
              "$PGBIN/initdb" -D "$DATA_DIR" --no-locale --encoding=UTF8 -A trust >/dev/null
            fi

            local port
            port="$(choose_port)"
            echo "Cluster ready at $DATA_DIR"
            echo "Assigned port: $port"
          }

          cmd_start() {
            cmd_init
            local port
            port="$(read_port)"

            if "$PGBIN/pg_ctl" -D "$DATA_DIR" status >/dev/null 2>&1; then
              echo "Postgres already running (port $port)"
            else
              echo "Starting Postgres on port $port"
              "$PGBIN/pg_ctl" -D "$DATA_DIR" -l "$LOG_FILE" -o "-p $port -k $RUN_DIR -c unix_socket_directories=$RUN_DIR" start
            fi

            for _ in $(seq 1 40); do
              if "$PGBIN/pg_isready" -q -h "$RUN_DIR" -p "$port" >/dev/null 2>&1; then
                break
              fi
              sleep 0.1
            done

            "$PGBIN/createdb" -h "$RUN_DIR" -p "$port" hrafnsyn_dev 2>/dev/null || true
            "$PGBIN/createdb" -h "$RUN_DIR" -p "$port" hrafnsyn_test 2>/dev/null || true

            echo ""
            echo "Postgres running"
            echo "  data: $DATA_DIR"
            echo "  port: $port"
            echo "  socket: $RUN_DIR"
            echo ""
            echo 'Run this in your shell: eval "$(pg-env)"'
          }

          cmd_stop() {
            if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
              echo "No local Postgres cluster to stop."
              return 0
            fi

            if "$PGBIN/pg_ctl" -D "$DATA_DIR" status >/dev/null 2>&1; then
              "$PGBIN/pg_ctl" -D "$DATA_DIR" stop -m fast
              echo "Stopped Postgres."
            else
              echo "Postgres is not running."
            fi
          }

          cmd_reset() {
            cmd_stop || true
            rm -rf "$BASE_DIR"
            echo "Removed $BASE_DIR"
          }

          cmd_isready() {
            local port
            port="$(read_port)"
            exec "$PGBIN/pg_isready" -h "$RUN_DIR" -p "$port"
          }

          cmd_status() {
            if [ ! -f "$DATA_DIR/PG_VERSION" ]; then
              echo "uninitialized"
              exit 1
            fi

            local port
            port="$(read_port)"

            if "$PGBIN/pg_ctl" -D "$DATA_DIR" status >/dev/null 2>&1; then
              echo "running"
              echo "  port: $port"
              echo "  data: $DATA_DIR"
              echo "  socket: $RUN_DIR"
            else
              echo "stopped"
              echo "  port: $port"
              echo "  data: $DATA_DIR"
            fi
          }

          cmd_env() {
            local port
            port="$(read_port)"

            cat <<EOF
export PGDEV_DIR="$BASE_DIR"
export PGPORT="$port"
export PGHOST="$RUN_DIR"
export DATABASE_URL="$(db_url hrafnsyn_dev)"
export TEST_DATABASE_URL="$(db_url hrafnsyn_test)"
EOF
          }

          cmd="$1"
          shift || true

          case "$cmd" in
            init) cmd_init "$@" ;;
            start) cmd_start "$@" ;;
            stop) cmd_stop "$@" ;;
            reset) cmd_reset "$@" ;;
            isready) cmd_isready "$@" ;;
            status) cmd_status "$@" ;;
            env) cmd_env "$@" ;;
            *)
              echo "Usage: pg-dev-core {init|start|stop|reset|isready|status|env}" >&2
              exit 1
              ;;
          esac
        '';

        pg-init = pkgs.writeShellScriptBin "pg-init" ''exec pg-dev-core init "$@"'';
        pg-start = pkgs.writeShellScriptBin "pg-start" ''exec pg-dev-core start "$@"'';
        pg-stop = pkgs.writeShellScriptBin "pg-stop" ''exec pg-dev-core stop "$@"'';
        pg-reset = pkgs.writeShellScriptBin "pg-reset" ''exec pg-dev-core reset "$@"'';
        pg-isready = pkgs.writeShellScriptBin "pg-isready" ''exec pg-dev-core isready "$@"'';
        pg-status = pkgs.writeShellScriptBin "pg-status" ''exec pg-dev-core status "$@"'';
        pg-env = pkgs.writeShellScriptBin "pg-env" ''exec pg-dev-core env "$@"'';
        app = pkgs.writeShellScriptBin "app" ''
          set -euo pipefail
          pg-reset
          pg-start
          eval "$(pg-env)"
          mix ecto.setup
          exec mix phx.server
        '';

        mixFodDeps = beamPackages.fetchMixDeps {
          pname = "hrafnsyn-mix-deps";
          version = "0.1.0";
          src = ./.;
          sha256 = "sha256-mnlWRHTi3A/UL//UHh9xmT1TkEj/FOVY4emG9bEk/dQ=";
        };
      in
      {
        packages.default = beamPackages.mixRelease {
          pname = "hrafnsyn";
          version = "0.1.0";
          src = ./.;

          inherit mixFodDeps;

          MIX_ESBUILD_PATH = "${esbuild}/bin/esbuild";
          MIX_TAILWIND_PATH = "${tailwindcss}/bin/tailwindcss";

          preBuild = ''
            mkdir -p _build/esbuild _build/tailwind deps
            ln -sfn ${heroiconsSrc} deps/heroicons
          '';

          postBuild = ''
            mix assets.deploy --no-deps-check
          '';

          fixupPhase = ''
            echo "hrafnsyn_cookie" > $out/releases/COOKIE
          '';
        };

        packages.hrafnsyn = self.packages.${system}.default;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            beamPackages.elixir
            beamPackages.erlang
            postgres
            nodejs_22
            esbuild
            tailwindcss
            git
            gcc
            gnumake
            pkg-config
            pg-dev-core
            pg-init
            pg-start
            pg-stop
            pg-reset
            pg-isready
            pg-status
            pg-env
            app
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            inotify-tools
          ];

          shellHook = ''
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
            export ERL_AFLAGS="-kernel shell_history enabled"
            export MIX_ESBUILD_PATH="${esbuild}/bin/esbuild"
            export MIX_TAILWIND_PATH="${tailwindcss}/bin/tailwindcss"

            mkdir -p deps
            ln -sfn ${heroiconsSrc} deps/heroicons

            printf '\n'
            printf '  \033[1;34mhrafnsyn\033[0m dev shell\n'
            printf '  \033[2m─────────────────────────────────\033[0m\n'
            printf '  \033[33mdb\033[0m   pg-start, pg-stop, pg-reset, pg-status\n'
            printf '  \033[33mapp\033[0m  pg-reset && pg-start && eval "$(pg-env)" && mix ecto.setup && mix phx.server\n'
            printf '\n'
          '';
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/hrafnsyn";
        };
      }))
    // {
      nixosModules.default = import ./nix/module.nix;
    };
}
