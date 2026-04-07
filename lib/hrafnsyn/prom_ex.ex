defmodule Hrafnsyn.PromEx do
  @moduledoc """
  PromEx configuration for Prometheus exposition and Grafana dashboards.
  """

  use PromEx, otp_app: :hrafnsyn

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Beam,
      {Plugins.Phoenix, router: HrafnsynWeb.Router, endpoint: HrafnsynWeb.Endpoint},
      {Plugins.Ecto, otp_app: :hrafnsyn, repos: [Hrafnsyn.Repo]},
      Hrafnsyn.PromEx.HrafnsynPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "datasource",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
