defmodule HrafnsynWeb.Plugs.ProxySSL do
  @moduledoc false
  @behaviour Plug

  import Bitwise

  alias HrafnsynWeb.Endpoint

  @forwarded_rewrite_headers [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    endpoint_config = Application.fetch_env!(:hrafnsyn, Endpoint)

    conn
    |> maybe_rewrite_from_trusted_proxy(endpoint_config)
    |> maybe_force_ssl(endpoint_config)
  end

  defp maybe_rewrite_from_trusted_proxy(conn, endpoint_config) do
    proxy_headers_config = Keyword.get(endpoint_config, :proxy_headers, [])
    trusted_proxies = Keyword.get(proxy_headers_config, :trusted_proxies, [])
    rewrite_on = Keyword.get(proxy_headers_config, :rewrite_on, @forwarded_rewrite_headers)

    if trusted_proxy?(conn.remote_ip, trusted_proxies) do
      Plug.RewriteOn.call(conn, rewrite_on)
    else
      conn
    end
  end

  defp maybe_force_ssl(conn, endpoint_config) do
    ssl_redirect_config = Keyword.get(endpoint_config, :ssl_redirect, [])

    if Keyword.get(ssl_redirect_config, :enabled, false) do
      ssl_redirect_config
      |> Keyword.delete(:enabled)
      |> Plug.SSL.init()
      |> then(&Plug.SSL.call(conn, &1))
    else
      conn
    end
  end

  defp trusted_proxy?(remote_ip, trusted_proxies) when is_tuple(remote_ip) do
    Enum.any?(trusted_proxies, &cidr_contains?(&1, remote_ip))
  end

  defp trusted_proxy?(_remote_ip, _trusted_proxies), do: false

  defp cidr_contains?(cidr, remote_ip) do
    with {:ok, {network_ip, prefix_length}} <- parse_cidr(cidr),
         {:ok, remote_ip_int, width} <- ip_to_integer(remote_ip),
         {:ok, network_ip_int, ^width} <- ip_to_integer(network_ip) do
      network_mask(width, prefix_length)
      |> then(fn mask ->
        (remote_ip_int &&& mask) == (network_ip_int &&& mask)
      end)
    else
      _error -> false
    end
  end

  defp parse_cidr(cidr) do
    case String.split(cidr, "/", parts: 2) do
      [address] ->
        with {:ok, ip} <- parse_ip(address),
             {:ok, _ip_int, width} <- ip_to_integer(ip) do
          {:ok, {ip, width}}
        end

      [address, prefix_length] ->
        with {:ok, ip} <- parse_ip(address),
             {prefix_length, ""} <- Integer.parse(prefix_length),
             {:ok, _ip_int, width} <- ip_to_integer(ip),
             true <- prefix_length >= 0 and prefix_length <= width do
          {:ok, {ip, prefix_length}}
        else
          _error -> :error
        end
    end
  end

  defp parse_ip(address) do
    address
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_address()
  end

  defp ip_to_integer({a, b, c, d}) do
    {:ok, Enum.reduce([a, b, c, d], 0, fn octet, acc -> (acc <<< 8) + octet end), 32}
  end

  defp ip_to_integer({a, b, c, d, e, f, g, h}) do
    {:ok, ipv6_hextets_to_integer([a, b, c, d, e, f, g, h]), 128}
  end

  defp ip_to_integer(_ip), do: :error

  defp ipv6_hextets_to_integer(hextets) do
    Enum.reduce(hextets, 0, fn hextet, acc -> (acc <<< 16) + hextet end)
  end

  defp network_mask(_width, 0), do: 0

  defp network_mask(width, prefix_length) do
    ((1 <<< prefix_length) - 1) <<< (width - prefix_length)
  end
end
