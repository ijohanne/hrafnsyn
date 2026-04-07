defmodule Hrafnsyn.Tracking.ExternalLinks do
  @moduledoc false

  @flightaware_base_url "https://www.flightaware.com"

  @type action :: %{label: String.t(), href: String.t(), description: String.t()}

  @spec aircraft_actions(map()) :: [action()]
  def aircraft_actions(track) do
    if track_field(track, :vehicle_type) == "plane" do
      [photo_action(track), flight_page_action(track)]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  @spec flightaware_photo_url(map()) :: String.t() | nil
  def flightaware_photo_url(track) do
    with registration when is_binary(registration) <-
           normalize_alphanumeric(track_field(track, :registration)) do
      "#{@flightaware_base_url}/photos/aircraft/#{registration}"
    end
  end

  @spec flightaware_flight_page_url(map()) :: String.t() | nil
  def flightaware_flight_page_url(track) do
    with identity when is_binary(identity) <- normalize_hex(track_field(track, :identity)),
         ident when is_binary(ident) <- normalize_alphanumeric(track_field(track, :callsign)) do
      "#{@flightaware_base_url}/live/modes/#{identity}/ident/#{ident}/redirect"
    end
  end

  defp photo_action(track) do
    with href when is_binary(href) <- flightaware_photo_url(track) do
      %{
        label: "Photos",
        href: href,
        description: "Open the FlightAware aircraft gallery for this registration."
      }
    end
  end

  defp flight_page_action(track) do
    with href when is_binary(href) <- flightaware_flight_page_url(track) do
      %{
        label: "Flight page",
        href: href,
        description: "Open the current flight page with live and planned-route context."
      }
    end
  end

  defp track_field(track, key) do
    Map.get(track, key) || Map.get(track, Atom.to_string(key))
  end

  defp normalize_alphanumeric(nil), do: nil

  defp normalize_alphanumeric(value) do
    value
    |> to_string()
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/u, "")
    |> blank_to_nil()
  end

  defp normalize_hex(nil), do: nil

  defp normalize_hex(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^0-9a-f]/u, "")
    |> blank_to_nil()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
