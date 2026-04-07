defmodule HrafnsynWeb.Plugs.ProxySSLTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias HrafnsynWeb.Endpoint
  alias HrafnsynWeb.Plugs.ProxySSL

  setup do
    original_config = Application.fetch_env!(:hrafnsyn, Endpoint)

    on_exit(fn ->
      Application.put_env(:hrafnsyn, Endpoint, original_config)
    end)

    :ok
  end

  test "rewrites forwarded scheme, host, and port for trusted proxies and marks cookies secure" do
    configure_endpoint(
      proxy_headers: [
        trusted_proxies: ["127.0.0.0/8"],
        rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]
      ],
      ssl_redirect: [enabled: false]
    )

    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "tracks.example.com")
      |> put_req_header("x-forwarded-port", "443")
      |> ProxySSL.call([])
      |> put_resp_cookie("session", "token")

    assert conn.scheme == :https
    assert conn.host == "tracks.example.com"
    assert conn.port == 443
    assert conn.resp_cookies["session"].secure
  end

  test "ignores forwarded headers from untrusted peers" do
    configure_endpoint(
      proxy_headers: [
        trusted_proxies: ["127.0.0.0/8"],
        rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]
      ],
      ssl_redirect: [enabled: false]
    )

    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {203, 0, 113, 10})
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "tracks.example.com")
      |> put_req_header("x-forwarded-port", "443")
      |> ProxySSL.call([])

    assert conn.scheme == :http
    assert conn.host == "www.example.com"
    assert conn.port == 80
  end

  test "adds hsts without redirecting trusted proxied https requests when ssl redirects are enabled" do
    configure_endpoint(
      proxy_headers: [
        trusted_proxies: ["127.0.0.0/8"],
        rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]
      ],
      ssl_redirect: [
        enabled: true,
        host: "tracks.example.com",
        exclude: [paths: ["/metrics"], hosts: ["localhost", "127.0.0.1"]]
      ]
    )

    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> put_req_header("x-forwarded-proto", "https")
      |> put_req_header("x-forwarded-host", "tracks.example.com")
      |> put_req_header("x-forwarded-port", "443")
      |> ProxySSL.call([])

    assert conn.scheme == :https
    assert conn.status == nil
    assert get_resp_header(conn, "strict-transport-security") != []
  end

  test "redirects direct http requests to https when ssl redirects are enabled" do
    configure_endpoint(
      proxy_headers: [
        trusted_proxies: ["127.0.0.0/8"],
        rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]
      ],
      ssl_redirect: [
        enabled: true,
        host: "tracks.example.com",
        exclude: [paths: ["/metrics"], hosts: ["localhost", "127.0.0.1"]]
      ]
    )

    conn =
      :get
      |> conn("/")
      |> Map.put(:host, "tracks.example.com")
      |> Map.put(:remote_ip, {198, 51, 100, 42})
      |> ProxySSL.call([])

    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["https://tracks.example.com/"]
  end

  defp configure_endpoint(overrides) do
    :hrafnsyn
    |> Application.fetch_env!(Endpoint)
    |> Keyword.merge(overrides)
    |> then(&Application.put_env(:hrafnsyn, Endpoint, &1))
  end
end
