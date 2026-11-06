defmodule Hrafnsyn.MobileLinksTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.MobileLinks

  test "handoff preserves identity and range with no credential-bearing parameters" do
    path = "/?vehicle=vessel&identity=A%26B+%2F+%C3%98&range=24&token=private&lat=36&lon=-5"
    link = URI.parse(MobileLinks.open_return_path(path))
    assert link.scheme == "hrafnsyn"
    assert link.host == "open"
    target = link.query |> URI.decode_query() |> Map.fetch!("url") |> URI.parse()
    assert target.host == URI.parse(HrafnsynWeb.Endpoint.url()).host

    assert URI.decode_query(target.query) == %{
             "vehicle" => "vessel",
             "identity" => "A&B / Ø",
             "range" => "24"
           }
  end

  test "only local shared track return paths become app links" do
    for path <- [
          nil,
          "/users/settings",
          "https://other.example/?vehicle=plane&identity=A",
          "//other.example/?vehicle=plane&identity=A",
          "/?vehicle=plane&identity=",
          "/?vehicle=car&identity=A",
          "/?vehicle=plane&identity=A&identity=B",
          "/?vehicle=plane&identity=%00",
          "/?vehicle=plane&identity=A&range=999",
          "/?vehicle=plane&identity=A#fragment"
        ] do
      assert MobileLinks.open_return_path(path) == nil, inspect(path)
    end
  end

  test "missing range defaults to six hours and invalid identity is rejected" do
    assert MobileLinks.open_return_path("/?vehicle=plane&identity=406ABC") =~ "range%3D6"
    refute MobileLinks.open_url("plane", String.duplicate("a", 257), 6)
    refute MobileLinks.open_url("plane", <<255>>, 6)
    refute MobileLinks.open_url("plane", "   ", 6)
    refute MobileLinks.open_url("plane", "\u0085", 6)
  end
end
