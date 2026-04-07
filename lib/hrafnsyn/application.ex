defmodule Hrafnsyn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Hrafnsyn.GRPC.Config, as: GRPCConfig

  @impl true
  def start(_type, _args) do
    children =
      [
        HrafnsynWeb.Telemetry,
        Hrafnsyn.Repo,
        {DNSCluster, query: Application.get_env(:hrafnsyn, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Hrafnsyn.PubSub},
        Hrafnsyn.Accounts.AdminBootstrap,
        Hrafnsyn.Collectors.Supervisor,
        HrafnsynWeb.Endpoint
      ] ++ prom_ex_children() ++ grpc_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hrafnsyn.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp grpc_children do
    if GRPCConfig.enabled?() do
      [
        {GRPC.Server.Supervisor,
         endpoint: Hrafnsyn.GRPC.Endpoint,
         port: GRPCConfig.port(),
         start_server: true,
         adapter_opts: [ip: GRPCConfig.listen_ip()]}
      ]
    else
      []
    end
  end

  defp prom_ex_children do
    if Application.get_env(:hrafnsyn, :enable_prom_ex?, true) do
      [Hrafnsyn.PromEx]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HrafnsynWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
