defmodule Hrafnsyn.Aircraft.MetadataTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.Aircraft.Metadata

  describe "derive/1" do
    test "derives country ranges from ICAO hex" do
      assert %{country: "Morocco", registration: nil} = Metadata.derive("020123")
      assert %{country: "Netherlands"} = Metadata.derive("4840D6")
      assert %{country: nil, registration: nil} = Metadata.derive("F00000")
    end

    test "derives best-effort registrations for supported allocation schemes" do
      assert %{country: "United States", registration: "N1"} = Metadata.derive("A00001")
      assert %{country: "France", registration: "F-GAAA"} = Metadata.derive("390000")
      assert %{country: "South Korea", registration: "HL7200"} = Metadata.derive("71BA00")
      assert %{country: "Japan", registration: "JA0000"} = Metadata.derive("840000")
    end

    test "returns nil fields for invalid identities" do
      assert %{country: nil, registration: nil} = Metadata.derive(nil)
      assert %{country: nil, registration: nil} = Metadata.derive("not-hex")
    end
  end
end
