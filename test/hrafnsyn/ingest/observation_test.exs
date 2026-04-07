defmodule Hrafnsyn.Ingest.ObservationTest do
  use ExUnit.Case, async: false

  alias Hrafnsyn.Aircraft.StaticDB
  alias Hrafnsyn.Ingest.Observation

  setup do
    config_key = {:hrafnsyn, Hrafnsyn.Aircraft.StaticDB}
    original_config = Application.get_env(elem(config_key, 0), elem(config_key, 1), [])

    Application.put_env(:hrafnsyn, Hrafnsyn.Aircraft.StaticDB, path: nil)
    assert :ok = StaticDB.reload()

    on_exit(fn ->
      Application.put_env(:hrafnsyn, Hrafnsyn.Aircraft.StaticDB, original_config)
      assert :ok = StaticDB.reload()
    end)

    :ok
  end

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

    test "enriches planes from the static aircraft DB before derived fallbacks" do
      observed_at = DateTime.utc_now(:second)
      path = write_aircraft_db_fixture!()

      Application.put_env(:hrafnsyn, Hrafnsyn.Aircraft.StaticDB, path: path)
      assert :ok = StaticDB.reload()

      assert {:ok, observation} =
               Observation.new(%{
                 vehicle_type: "plane",
                 identity: "A00001",
                 observed_at: observed_at
               })

      assert observation.country == "United States"
      assert observation.registration == "N54321"
      assert observation.aircraft_type == "GLF4"
      assert observation.type_description == "Landplane, 2 jet engines (L2J)"
      assert observation.wake_turbulence_category == "M"
    end
  end

  defp write_aircraft_db_fixture! do
    path =
      Path.join(
        System.tmp_dir!(),
        "hrafnsyn-aircraft-db-#{System.unique_integer([:positive])}.ndjson"
      )

    File.write!(
      path,
      ~s({"identity":"A00001","registration":"N54321","aircraft_type":"GLF4","type_description":"L2J","wake_turbulence_category":"M"}\n)
    )

    path
  end
end
