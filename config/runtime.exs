import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/hrafnsyn start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :hrafnsyn, HrafnsynWeb.Endpoint, server: true
end

listen_address = System.get_env("LISTEN_ADDRESS", "127.0.0.1")

listen_ip =
  case :inet.parse_address(String.to_charlist(listen_address)) do
    {:ok, ip} -> ip
    _ -> {127, 0, 0, 1}
  end

grpc_listen_address = System.get_env("GRPC_LISTEN_ADDRESS", "127.0.0.1")

grpc_listen_ip =
  case :inet.parse_address(String.to_charlist(grpc_listen_address)) do
    {:ok, ip} -> ip
    _ -> {127, 0, 0, 1}
  end

if sources_json = System.get_env("HRAFNSYN_SOURCES_JSON") do
  sources =
    sources_json
    |> Jason.decode!()
    |> Enum.map(fn source ->
      source
      |> Enum.into(%{}, fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Map.update(:vehicle_type, nil, &String.to_existing_atom/1)
      |> Map.update(:adapter, nil, &String.to_existing_atom/1)
    end)

  config :hrafnsyn, Hrafnsyn.Collectors, sources: sources
end

if map_style_url = System.get_env("HRAFNSYN_MAP_STYLE_URL") do
  config :hrafnsyn, :map_style_url, map_style_url
end

if metrics_port = System.get_env("METRICS_PORT") do
  config :hrafnsyn, Hrafnsyn.PromEx,
    metrics_server: [
      port: String.to_integer(metrics_port),
      path: "/metrics"
    ]
end

if public_readonly = System.get_env("HRAFNSYN_PUBLIC_READONLY") do
  config :hrafnsyn, :public_readonly?, public_readonly in ~w(true 1 yes on)
end

if bootstrap_users_json = System.get_env("HRAFNSYN_BOOTSTRAP_USERS_JSON") do
  bootstrap_users =
    bootstrap_users_json
    |> Jason.decode!()
    |> Enum.map(fn {username, attrs} ->
      Enum.reduce(attrs, %{username: username}, fn
        {"email", value}, acc -> Map.put(acc, :email, value)
        {"hashed_password", value}, acc -> Map.put(acc, :hashed_password, value)
        {"is_admin", value}, acc -> Map.put(acc, :is_admin, value)
        {"password", value}, acc -> Map.put(acc, :password, value)
        {_key, _value}, acc -> acc
      end)
    end)

  config :hrafnsyn, :bootstrap_users, bootstrap_users
end

config :hrafnsyn, Hrafnsyn.GRPC,
  enabled: System.get_env("GRPC_PORT") not in [nil, ""],
  listen_ip: grpc_listen_ip,
  port: String.to_integer(System.get_env("GRPC_PORT", "50051")),
  access_token_ttl_seconds:
    String.to_integer(System.get_env("HRAFNSYN_JWT_ACCESS_TTL_SECONDS", "900")),
  refresh_token_ttl_seconds:
    String.to_integer(System.get_env("HRAFNSYN_JWT_REFRESH_TTL_SECONDS", "2592000")),
  jwt_secret:
    System.get_env("HRAFNSYN_JWT_SIGNING_SECRET") ||
      System.get_env("SECRET_KEY_BASE") ||
      "dev-grpc-secret"

config :hrafnsyn, HrafnsynWeb.Endpoint,
  http: [ip: listen_ip, port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  if database_url = System.get_env("DATABASE_URL") do
    config :hrafnsyn, Hrafnsyn.Repo,
      # ssl: true,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      # For machines with several cores, consider starting multiple pools of `pool_size`
      # pool_count: 4,
      socket_options: maybe_ipv6
  else
    db_host = System.get_env("DATABASE_HOST", "/run/postgresql")
    db_name = System.get_env("DATABASE_NAME", "hrafnsyn")
    db_user = System.get_env("DATABASE_USER", "hrafnsyn")
    db_pass = System.get_env("DATABASE_PASSWORD")

    host_opts =
      if String.starts_with?(db_host, "/"),
        do: [socket_dir: db_host],
        else: [hostname: db_host, socket_options: maybe_ipv6]

    config :hrafnsyn, Hrafnsyn.Repo, [
      {:database, db_name},
      {:username, db_user},
      {:password, db_pass},
      {:pool_size, String.to_integer(System.get_env("POOL_SIZE") || "10")}
      | host_opts
    ]
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  scheme = System.get_env("HRAFNSYN_SCHEME", "https")
  external_port = String.to_integer(System.get_env("HRAFNSYN_EXTERNAL_PORT", "443"))
  force_ssl? = System.get_env("HRAFNSYN_FORCE_SSL", "true") in ~w(true 1 yes on)
  trusted_proxies =
    case System.get_env("HRAFNSYN_TRUSTED_PROXIES") do
      nil -> []
      proxies -> String.split(proxies, ",", trim: true) |> Enum.map(&String.trim/1)
    end

  config :hrafnsyn, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :hrafnsyn, HrafnsynWeb.Endpoint,
    url: [host: host, port: external_port, scheme: scheme],
    proxy_headers: [
      trusted_proxies: trusted_proxies,
      rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]
    ],
    http: [
      ip: listen_ip
    ],
    secret_key_base: secret_key_base

  if force_ssl? do
    config :hrafnsyn, HrafnsynWeb.Endpoint,
      ssl_redirect: [
        enabled: true,
        host: host,
        exclude: [
          paths: ["/metrics"],
          hosts: ["localhost", "127.0.0.1"]
        ]
      ]
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :hrafnsyn, HrafnsynWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :hrafnsyn, HrafnsynWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :hrafnsyn, Hrafnsyn.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
