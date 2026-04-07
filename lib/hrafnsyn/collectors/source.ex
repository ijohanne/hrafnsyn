defmodule Hrafnsyn.Collectors.Source do
  @moduledoc "Runtime configuration for one upstream tracking source."

  @enforce_keys [:id, :name, :vehicle_type, :adapter, :base_url]
  defstruct [
    :id,
    :name,
    :vehicle_type,
    :adapter,
    :base_url,
    poll_interval_ms: 2_500,
    enabled: true
  ]

  def from_map(attrs) do
    struct(__MODULE__, attrs)
  end
end
