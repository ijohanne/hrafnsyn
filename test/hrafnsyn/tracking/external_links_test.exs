defmodule Hrafnsyn.Tracking.ExternalLinksTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.Tracking.ExternalLinks

  test "builds normalized FlightAware photo and flight page URLs for aircraft" do
    track = %{
      vehicle_type: "plane",
      identity: "406ABC",
      callsign: "AFR 69ZJ",
      registration: "F-GZNE"
    }

    assert ExternalLinks.aircraft_actions(track) == [
             %{
               label: "Photos",
               href: "https://www.flightaware.com/photos/aircraft/FGZNE",
               description: "Open the FlightAware aircraft gallery for this registration."
             },
             %{
               label: "Flight page",
               href: "https://www.flightaware.com/live/modes/406abc/ident/AFR69ZJ/redirect",
               description: "Open the current flight page with live and planned-route context."
             }
           ]
  end

  test "omits actions when the aircraft does not have enough data" do
    assert ExternalLinks.aircraft_actions(%{
             vehicle_type: "plane",
             identity: "406ABC",
             callsign: nil,
             registration: nil
           }) == []
  end

  test "never builds aircraft actions for vessels" do
    assert ExternalLinks.aircraft_actions(%{
             vehicle_type: "vessel",
             identity: "242080116",
             callsign: "C6FQ7",
             registration: "IMO 9262130"
           }) == []
  end
end
