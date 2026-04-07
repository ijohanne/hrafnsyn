defmodule Hrafnsyn.CountryFlagsTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.CountryFlags

  test "formats known country names and codes as emoji plus alpha2 code" do
    assert CountryFlags.format("Bahamas") == "🇧🇸 BS"
    assert CountryFlags.format("gi") == "🇬🇮 GI"
    assert CountryFlags.format("South Korea") == "🇰🇷 KR"
    assert CountryFlags.format("Curaçao") == "🇨🇼 CW"
  end

  test "falls back to the raw country string when it cannot map a flag" do
    assert CountryFlags.format("Atlantis") == "Atlantis"
    assert CountryFlags.format("  ") == nil
    assert CountryFlags.format(nil) == nil
  end
end
