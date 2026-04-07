defmodule Hrafnsyn.GRPC.Config do
  @moduledoc false

  @default_port 50_051
  @default_ip {127, 0, 0, 1}
  @default_access_ttl_seconds 15 * 60
  @default_refresh_ttl_seconds 30 * 24 * 60 * 60

  @spec enabled?() :: boolean()
  def enabled? do
    grpc_config()
    |> Keyword.get(:enabled, false)
  end

  @spec port() :: pos_integer()
  def port do
    grpc_config()
    |> Keyword.get(:port, @default_port)
  end

  @spec listen_ip() :: :inet.ip_address()
  def listen_ip do
    grpc_config()
    |> Keyword.get(:listen_ip, @default_ip)
  end

  @spec access_token_ttl_seconds() :: pos_integer()
  def access_token_ttl_seconds do
    grpc_config()
    |> Keyword.get(:access_token_ttl_seconds, @default_access_ttl_seconds)
  end

  @spec refresh_token_ttl_seconds() :: pos_integer()
  def refresh_token_ttl_seconds do
    grpc_config()
    |> Keyword.get(:refresh_token_ttl_seconds, @default_refresh_ttl_seconds)
  end

  @spec jwt_secret() :: binary()
  def jwt_secret do
    grpc_config()
    |> Keyword.fetch!(:jwt_secret)
  end

  defp grpc_config do
    Application.get_env(:hrafnsyn, Hrafnsyn.GRPC, [])
  end
end
