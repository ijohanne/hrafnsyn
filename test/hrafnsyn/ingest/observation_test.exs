defmodule Hrafnsyn.Ingest.ObservationTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.Ingest.Observation

  describe "new/1" do
    test "fills plane country and registration from ICAO metadata when missing" do
      observed_at = DateTime.utc_now(:second)

      assert {:ok, observation} =
               Observation.new(%{
                 vehicle_type: "plane",
                 identity: "A00001",
                 observed_at: observed_at
               })

      assert observation.country == "United States"
      assert observation.registration == "N1"
      assert observation.display_name == "N1"
    end

    test "prefers source plane metadata over derived fallbacks" do
      observed_at = DateTime.utc_now(:second)

      assert {:ok, observation} =
               Observation.new(%{
                 vehicle_type: "plane",
                 identity: "A00001",
                 registration: "N123ZZ",
                 country: "Canada",
                 observed_at: observed_at
               })

      assert observation.country == "Canada"
      assert observation.registration == "N123ZZ"
    end
  end
end
