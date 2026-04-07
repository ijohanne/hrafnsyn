defmodule Hrafnsyn.Ingest.Observation do
  @moduledoc """
  Canonical normalized observation shape used by the ingest pipeline.
  """

  @enforce_keys [:vehicle_type, :identity, :observed_at]
  defstruct [
    :vehicle_type,
    :identity,
    :display_name,
    :callsign,
    :registration,
    :country,
    :category,
    :status,
    :destination,
    :latitude,
    :longitude,
    :speed,
    :heading,
    :altitude,
    :observed_at,
    :last_payload
  ]

  @fields [
    :vehicle_type,
    :identity,
    :display_name,
    :callsign,
    :registration,
    :country,
    :category,
    :status,
    :destination,
    :latitude,
    :longitude,
    :speed,
    :heading,
    :altitude,
    :observed_at,
    :last_payload
  ]
  @vehicle_types ~w(plane vessel)

  @type t :: %__MODULE__{
          vehicle_type: String.t(),
          identity: String.t(),
          display_name: String.t() | nil,
          callsign: String.t() | nil,
          registration: String.t() | nil,
          country: String.t() | nil,
          category: String.t() | nil,
          status: String.t() | nil,
          destination: String.t() | nil,
          latitude: float() | nil,
          longitude: float() | nil,
          speed: float() | nil,
          heading: float() | nil,
          altitude: integer() | nil,
          observed_at: DateTime.t(),
          last_payload: map() | nil
        }

  @spec normalize_many([map() | t()]) :: [t()]
  def normalize_many(observations) do
    Enum.reduce(observations, [], fn observation, acc ->
      case new(observation) do
        {:ok, normalized} -> [normalized | acc]
        {:error, _reason} -> acc
      end
    end)
    |> Enum.reverse()
  end

  @spec new(map() | t()) :: {:ok, t()} | {:error, atom()}
  def new(%__MODULE__{} = observation) do
    observation
    |> Map.from_struct()
    |> new()
  end

  def new(attrs) when is_map(attrs) do
    observation =
      attrs
      |> Map.take(@fields)
      |> then(&struct(__MODULE__, &1))
      |> normalize()

    validate(observation)
  end

  @spec to_track_attrs(t()) :: map()
  def to_track_attrs(%__MODULE__{} = observation) do
    Map.take(observation, [
      :vehicle_type,
      :identity,
      :display_name,
      :callsign,
      :registration,
      :country,
      :category,
      :status,
      :destination,
      :latitude,
      :longitude,
      :speed,
      :heading,
      :altitude,
      :observed_at,
      :last_payload
    ])
  end

  @spec to_point_attrs(t()) :: map()
  def to_point_attrs(%__MODULE__{} = observation) do
    Map.take(observation, [
      :vehicle_type,
      :observed_at,
      :latitude,
      :longitude,
      :speed,
      :heading,
      :altitude
    ])
  end

  @spec search_fields(t()) :: map()
  def search_fields(%__MODULE__{} = observation) do
    Map.take(observation, [
      :identity,
      :display_name,
      :callsign,
      :registration,
      :destination,
      :country
    ])
  end

  defp normalize(observation) do
    %__MODULE__{
      observation
      | vehicle_type: observation.vehicle_type |> to_string() |> String.trim(),
        identity: observation.identity |> to_string() |> String.trim(),
        display_name: normalize_text(observation.display_name),
        callsign: normalize_text(observation.callsign),
        registration: normalize_text(observation.registration),
        country: normalize_text(observation.country),
        category: normalize_text(observation.category),
        status: normalize_text(observation.status),
        destination: normalize_text(observation.destination),
        latitude: normalize_float(observation.latitude),
        longitude: normalize_float(observation.longitude),
        speed: normalize_float(observation.speed),
        heading: normalize_float(observation.heading),
        altitude: normalize_integer(observation.altitude),
        observed_at: normalize_datetime(observation.observed_at),
        last_payload: normalize_payload(observation.last_payload)
    }
    |> fill_display_name()
  end

  defp fill_display_name(%__MODULE__{} = observation) do
    fallback =
      observation.display_name ||
        observation.callsign ||
        observation.registration ||
        observation.identity

    %{observation | display_name: fallback}
  end

  defp validate(
         %__MODULE__{vehicle_type: vehicle_type, identity: identity, observed_at: %DateTime{}} =
           observation
       )
       when vehicle_type in @vehicle_types and identity != "" do
    {:ok, observation}
  end

  defp validate(%__MODULE__{observed_at: nil}), do: {:error, :missing_observed_at}
  defp validate(%__MODULE__{identity: ""}), do: {:error, :missing_identity}

  defp validate(%__MODULE__{vehicle_type: vehicle_type}) when vehicle_type not in @vehicle_types,
    do: {:error, :invalid_vehicle_type}

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(_value), do: nil

  defp normalize_float(value) when is_float(value), do: value
  defp normalize_float(value) when is_integer(value), do: value / 1
  defp normalize_float(_value), do: nil

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_float(value), do: trunc(value)
  defp normalize_integer(_value), do: nil

  defp normalize_datetime(%DateTime{} = value), do: DateTime.truncate(value, :second)

  defp normalize_datetime(%NaiveDateTime{} = value) do
    value
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_payload(value) when is_map(value), do: value
  defp normalize_payload(_value), do: nil
end
