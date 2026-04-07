defmodule Hrafnsyn.Aircraft.TypeDescriptionTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.Aircraft.TypeDescription

  test "expands known ICAO aircraft description codes" do
    assert TypeDescription.expand("L2J") == "Landplane, 2 jet engines (L2J)"
    assert TypeDescription.expand("h1t") == "Helicopter, 1 turbine engine (H1T)"
  end

  test "passes through unknown values unchanged" do
    assert TypeDescription.expand("mystery") == "MYSTERY"
  end
end
