defmodule Hrafnsyn.Devices.Pruner do
  @moduledoc "Removes device identifiers after their thirty-day retention window."
  use GenServer
  alias Hrafnsyn.Devices

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :prune, :timer.minutes(1))
    {:ok, nil}
  end

  @impl true
  def handle_info(:prune, state) do
    Devices.prune_expired_invitations()
    Process.send_after(self(), :prune, :timer.hours(1))
    {:noreply, state}
  end
end
