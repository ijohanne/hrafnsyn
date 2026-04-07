defmodule Hrafnsyn.Collectors.Config do
  @moduledoc false

  alias Hrafnsyn.Collectors.Source

  def list_sources do
    :hrafnsyn
    |> Application.get_env(Hrafnsyn.Collectors, [])
    |> Keyword.get(:sources, [])
    |> Enum.map(&Source.from_map/1)
    |> Enum.filter(& &1.enabled)
  end
end
