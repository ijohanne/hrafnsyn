defmodule Hrafnsyn.Collectors.Worker do
  @moduledoc """
  Polls one configured source on a fixed cadence and ingests normalized observations.
  """

  use GenServer

  alias Hrafnsyn.Collectors.Source
  alias Hrafnsyn.Ingest

  def start_link(%Source{} = source) do
    GenServer.start_link(__MODULE__, source, name: via(source.id))
  end

  defp via(id), do: {:global, {__MODULE__, id}}

  @impl true
  def init(source) do
    send(self(), :poll)
    {:ok, source}
  end

  @impl true
  def handle_info(:poll, source) do
    _ = instrument_poll(source)
    Process.send_after(self(), :poll, source.poll_interval_ms)
    {:noreply, source}
  end

  defp instrument_poll(source) do
    started_at = System.monotonic_time()
    result = poll(source)

    duration_seconds =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond) /
        1_000_000

    :telemetry.execute(
      [:hrafnsyn, :collector, :poll, :stop],
      %{
        count: 1,
        duration_seconds: duration_seconds
      },
      %{
        source_id: source.id,
        vehicle_type: Atom.to_string(source.vehicle_type),
        result: telemetry_result(result)
      }
    )

    result
  end

  defp poll(%Source{adapter: :dump1090} = source) do
    url = URI.merge(source.base_url, "/data/aircraft.json") |> to_string()

    with {:ok, response} <- Req.get(url: url),
         {:ok, payload} <- decode_json_body(response.body) do
      now = payload["now"] || System.os_time(:second)

      observations =
        payload["aircraft"]
        |> List.wrap()
        |> Enum.flat_map(&normalize_plane(source, &1, now))

      Ingest.ingest_batch(source, observations)
    end
  end

  defp poll(%Source{adapter: :ais_catcher} = source) do
    url = URI.merge(source.base_url, "/api/ships_array.json") |> to_string()

    with {:ok, response} <- Req.get(url: url),
         {:ok, payload} <- decode_json_body(response.body) do
      now = DateTime.utc_now(:second)

      observations =
        payload["values"]
        |> List.wrap()
        |> Enum.flat_map(&normalize_vessel(source, &1, now))

      Ingest.ingest_batch(source, observations)
    end
  end

  defp normalize_plane(source, aircraft, now) do
    with latitude when is_number(latitude) <- aircraft["lat"],
         longitude when is_number(longitude) <- aircraft["lon"],
         identity when is_binary(identity) <- aircraft["hex"] do
      observed_at =
        now
        |> unix_to_datetime()
        |> DateTime.add(-trunc(aircraft["seen"] || 0), :second)

      callsign =
        aircraft["flight"]
        |> normalize_text()

      [
        %{
          vehicle_type: Atom.to_string(source.vehicle_type),
          identity: String.upcase(identity),
          display_name: callsign || String.upcase(identity),
          callsign: callsign,
          registration: normalize_text(aircraft["r"]),
          country: nil,
          category: aircraft["category"],
          status: if(aircraft["alt_baro"], do: "airborne", else: "unknown"),
          destination: nil,
          latitude: latitude,
          longitude: longitude,
          speed: aircraft["gs"],
          heading: aircraft["track"],
          altitude: normalize_altitude(aircraft["alt_baro"]),
          observed_at: observed_at,
          last_payload: aircraft
        }
      ]
    else
      _ -> []
    end
  end

  defp normalize_vessel(source, values, now) when is_list(values) do
    keys = [
      "mmsi",
      "lat",
      "lon",
      "distance",
      "bearing",
      "level",
      "count",
      "ppm",
      "approx",
      "heading",
      "cog",
      "speed",
      "to_bow",
      "to_stern",
      "to_starboard",
      "to_port",
      "last_group",
      "group_mask",
      "shiptype",
      "mmsi_type",
      "shipclass",
      "msg_type",
      "country",
      "status",
      "draught",
      "eta_month",
      "eta_day",
      "eta_hour",
      "eta_minute",
      "imo",
      "callsign",
      "shipname",
      "destination",
      "last_signal",
      "flags",
      "validated",
      "channels",
      "altitude",
      "received_stations"
    ]

    vessel =
      keys
      |> Enum.zip(values)
      |> Enum.into(%{})

    with latitude when is_number(latitude) <- vessel["lat"],
         longitude when is_number(longitude) <- vessel["lon"],
         mmsi when not is_nil(mmsi) <- vessel["mmsi"] do
      observed_at =
        now
        |> DateTime.add(-trunc(vessel["last_signal"] || 0), :second)

      callsign = normalize_text(vessel["callsign"])
      name = normalize_text(vessel["shipname"])

      [
        %{
          vehicle_type: Atom.to_string(source.vehicle_type),
          identity: to_string(mmsi),
          display_name: name || callsign || to_string(mmsi),
          callsign: callsign,
          registration: vessel["imo"] && "IMO #{vessel["imo"]}",
          country: vessel["country"],
          category: vessel["shipclass"] && "class #{vessel["shipclass"]}",
          status: vessel["status"] && Integer.to_string(vessel["status"]),
          destination: normalize_text(vessel["destination"]),
          latitude: latitude,
          longitude: longitude,
          speed: vessel["speed"],
          heading: vessel["cog"] || vessel["heading"],
          altitude: normalize_altitude(vessel["altitude"]),
          observed_at: observed_at,
          last_payload: vessel
        }
      ]
    else
      _ -> []
    end
  end

  defp normalize_text(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_text(_), do: nil

  defp normalize_altitude(value) when is_integer(value), do: value
  defp normalize_altitude(value) when is_float(value), do: trunc(value)
  defp normalize_altitude("ground"), do: 0
  defp normalize_altitude(_), do: nil

  defp decode_json_body(body) when is_binary(body), do: Jason.decode(body)
  defp decode_json_body(body) when is_map(body), do: {:ok, body}
  defp decode_json_body(_body), do: {:error, :invalid_body}

  defp unix_to_datetime(value) when is_float(value), do: value |> trunc() |> unix_to_datetime()
  defp unix_to_datetime(value) when is_integer(value), do: DateTime.from_unix!(value)

  defp telemetry_result({:ok, _value}), do: "ok"
  defp telemetry_result(:ok), do: "ok"
  defp telemetry_result(_other), do: "error"
end
