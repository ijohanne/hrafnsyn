defmodule Hrafnsyn.GRPC.Helpers do
  @moduledoc false

  alias Hrafnsyn.Collectors.Source

  def timestamp(nil), do: nil

  def timestamp(%DateTime{} = value) do
    %Google.Protobuf.Timestamp{
      seconds: DateTime.to_unix(value),
      nanos: value.microsecond |> elem(0) |> Kernel.*(1_000)
    }
  end

  def timestamp(%NaiveDateTime{} = value) do
    value
    |> DateTime.from_naive!("Etc/UTC")
    |> timestamp()
  end

  def vehicle_type_to_proto(:plane), do: :VEHICLE_TYPE_PLANE
  def vehicle_type_to_proto("plane"), do: :VEHICLE_TYPE_PLANE
  def vehicle_type_to_proto(:vessel), do: :VEHICLE_TYPE_VESSEL
  def vehicle_type_to_proto("vessel"), do: :VEHICLE_TYPE_VESSEL
  def vehicle_type_to_proto(_other), do: :VEHICLE_TYPE_UNSPECIFIED

  def vehicle_type_from_proto(:VEHICLE_TYPE_PLANE), do: {:ok, :plane}
  def vehicle_type_from_proto(:VEHICLE_TYPE_VESSEL), do: {:ok, :vessel}
  def vehicle_type_from_proto(1), do: {:ok, :plane}
  def vehicle_type_from_proto(2), do: {:ok, :vessel}
  def vehicle_type_from_proto(_other), do: {:error, :invalid_vehicle_type}

  def source_descriptor(%Source{} = source) do
    %Hrafnsyn.V1.SourceDescriptor{
      id: source.id,
      name: source.name,
      vehicle_type: vehicle_type_to_proto(source.vehicle_type),
      adapter: source.adapter |> to_string()
    }
  end

  def active_counts(%{total: total, planes: planes, vessels: vessels}) do
    %Hrafnsyn.V1.ActiveCounts{
      total: total,
      planes: planes,
      vessels: vessels
    }
  end

  def user_profile(nil), do: nil

  def user_profile(%{id: id, username: username, email: email, is_admin: is_admin}) do
    %Hrafnsyn.V1.UserProfile{id: id, username: username, email: email || "", is_admin: is_admin}
  end

  def user_profile(user) do
    %Hrafnsyn.V1.UserProfile{
      id: user.id,
      username: user.username,
      email: user.email || "",
      is_admin: user.is_admin
    }
  end

  def session_info(%{
        id: id,
        current: current,
        created_at: created_at,
        last_used_at: last_used_at,
        expires_at: expires_at,
        revoked_at: revoked_at
      }) do
    %Hrafnsyn.V1.SessionInfo{
      id: id,
      current: current,
      created_at: timestamp(created_at),
      last_used_at: timestamp(last_used_at),
      expires_at: timestamp(expires_at),
      revoked_at: timestamp(revoked_at)
    }
  end

  def token_pair(%{
        access_token: access_token,
        refresh_token: refresh_token,
        access_token_expires_at: access_token_expires_at,
        refresh_token_expires_at: refresh_token_expires_at,
        session: session,
        user: user
      }) do
    %Hrafnsyn.V1.TokenPair{
      access_token: access_token,
      refresh_token: refresh_token,
      access_token_expires_at: timestamp(access_token_expires_at),
      refresh_token_expires_at: timestamp(refresh_token_expires_at),
      session: session_info(session),
      user: user_profile(user)
    }
  end

  def track_summary(track) do
    {latitude, longitude, speed_knots, heading_degrees, altitude_feet} = summary_metrics(track)
    summary_strings = summary_strings(track)

    %Hrafnsyn.V1.TrackSummary{
      id: track.id,
      vehicle_type: vehicle_type_to_proto(track.vehicle_type),
      identity: summary_strings.identity,
      latest_source_id: track.latest_source_id || "",
      latest_source_name: track.latest_source_name || "",
      display_name: summary_strings.display_name,
      callsign: summary_strings.callsign,
      registration: summary_strings.registration,
      country: summary_strings.country,
      category: summary_strings.category,
      status: summary_strings.status,
      destination: summary_strings.destination,
      latitude: latitude,
      longitude: longitude,
      speed_knots: speed_knots,
      heading_degrees: heading_degrees,
      altitude_feet: altitude_feet,
      observed_at: timestamp(track.observed_at)
    }
  end

  def track_point(point) do
    %Hrafnsyn.V1.TrackPoint{
      id: point.id || "",
      track_id: point.track_id || "",
      source_id: point.source_id || "",
      source_name: point.source_name || "",
      vehicle_type: vehicle_type_to_proto(point.vehicle_type),
      latitude: normalize_float(point.latitude),
      longitude: normalize_float(point.longitude),
      speed_knots: normalize_float(point.speed),
      heading_degrees: normalize_float(point.heading),
      altitude_feet: point.altitude || 0,
      observed_at: timestamp(point.observed_at)
    }
  end

  def route_stats(%{distance_meters: distance_meters, observed_seconds: observed_seconds}) do
    %Hrafnsyn.V1.RouteStats{
      distance_meters: normalize_float(distance_meters),
      observed_seconds: observed_seconds
    }
  end

  def grpc_source(%Hrafnsyn.V1.SourceDescriptor{} = source) do
    with {:ok, vehicle_type} <- vehicle_type_from_proto(source.vehicle_type) do
      {:ok,
       %Source{
         id: source.id,
         name: source.name,
         vehicle_type: vehicle_type,
         adapter: :grpc,
         base_url: "grpc://#{source.id}"
       }}
    end
  end

  def observation_attrs(%Hrafnsyn.V1.Observation{} = observation) do
    with {:ok, vehicle_type} <- vehicle_type_from_proto(observation.vehicle_type),
         {:ok, observed_at} <- timestamp_to_datetime(observation.observed_at),
         {:ok, last_payload} <- decode_payload(observation.raw_payload_json) do
      {:ok,
       %{
         vehicle_type: Atom.to_string(vehicle_type),
         identity: blank_to_nil(observation.identity),
         display_name: blank_to_nil(observation.display_name),
         callsign: blank_to_nil(observation.callsign),
         registration: blank_to_nil(observation.registration),
         country: blank_to_nil(observation.country),
         category: blank_to_nil(observation.category),
         status: blank_to_nil(observation.status),
         destination: blank_to_nil(observation.destination),
         latitude: zero_to_nil(observation.latitude),
         longitude: zero_to_nil(observation.longitude),
         speed: zero_to_nil(observation.speed_knots),
         heading: zero_to_nil(observation.heading_degrees),
         altitude: zero_to_nil(observation.altitude_feet),
         observed_at: observed_at,
         last_payload: last_payload
       }}
    end
  end

  def auth_context(stream) do
    case stream.local do
      %{auth: auth} -> auth
      _other -> nil
    end
  end

  defp timestamp_to_datetime(nil), do: {:error, :missing_timestamp}

  defp timestamp_to_datetime(%Google.Protobuf.Timestamp{seconds: seconds, nanos: nanos}) do
    DateTime.from_unix(seconds, :second)
    |> case do
      {:ok, value} -> {:ok, %{value | microsecond: {div(nanos, 1_000), 6}}}
      {:error, _reason} -> {:error, :invalid_timestamp}
    end
  end

  defp decode_payload(<<>>), do: {:ok, nil}
  defp decode_payload(nil), do: {:ok, nil}

  defp decode_payload(raw_payload_json) when is_binary(raw_payload_json) do
    case Jason.decode(raw_payload_json) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, _payload} -> {:error, :invalid_payload}
      {:error, _reason} -> {:error, :invalid_payload}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp normalize_float(nil), do: 0.0
  defp normalize_float(value) when is_integer(value), do: value / 1
  defp normalize_float(value), do: value

  defp summary_metrics(track) do
    {
      normalize_float(track.latitude),
      normalize_float(track.longitude),
      normalize_float(track.speed),
      normalize_float(track.heading),
      track.altitude || 0
    }
  end

  defp summary_strings(track) do
    %{
      identity: or_empty(track.identity),
      display_name: or_empty(track.display_name),
      callsign: or_empty(track.callsign),
      registration: or_empty(track.registration),
      country: or_empty(track.country),
      category: or_empty(track.category),
      status: or_empty(track.status),
      destination: or_empty(track.destination)
    }
  end

  defp or_empty(nil), do: ""
  defp or_empty(value), do: value

  defp zero_to_nil(0), do: nil
  defp zero_to_nil(value) when value in [+0.0, -0.0], do: nil
  defp zero_to_nil(value), do: value
end
