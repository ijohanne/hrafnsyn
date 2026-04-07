defmodule Hrafnsyn.Collectors.Supervisor do
  @moduledoc """
  Starts one long-lived collector GenServer per configured target.
  """

  use Supervisor

  alias Hrafnsyn.Collectors.{Config, Worker}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = Enum.map(Config.list_sources(), &{Worker, &1})
    Supervisor.init(children, strategy: :one_for_one)
  end
end
