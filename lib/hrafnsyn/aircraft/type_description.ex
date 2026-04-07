defmodule Hrafnsyn.Aircraft.TypeDescription do
  @moduledoc false

  @aircraft_classes %{
    "A" => "Amphibian",
    "G" => "Gyrocopter",
    "H" => "Helicopter",
    "L" => "Landplane",
    "S" => "Seaplane",
    "T" => "Tiltrotor"
  }

  @engine_types %{
    "E" => "electric",
    "J" => "jet",
    "P" => "piston",
    "R" => "rocket",
    "T" => "turbine"
  }

  @spec expand(String.t() | nil) :: String.t() | nil
  def expand(value) when is_binary(value) do
    trimmed =
      value
      |> String.trim()
      |> String.upcase()

    case trimmed do
      <<aircraft_class::binary-size(1), count::binary-size(1), engine_type::binary-size(1)>> =
          code ->
        with aircraft_label when is_binary(aircraft_label) <-
               Map.get(@aircraft_classes, aircraft_class),
             {engine_count, ""} <- Integer.parse(count),
             engine_label when is_binary(engine_label) <- Map.get(@engine_types, engine_type) do
          "#{aircraft_label}, #{engine_count} #{engine_label} #{engine_word(engine_count)} (#{code})"
        else
          _other -> code
        end

      "" ->
        nil

      other ->
        other
    end
  end

  def expand(_value), do: nil

  defp engine_word(1), do: "engine"
  defp engine_word(_count), do: "engines"
end
