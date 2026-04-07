defmodule Hrafnsyn.Tracking.TrackPoint do
  use Ecto.Schema
  import Ecto.Changeset
  alias Geo.Point

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "track_points" do
    field :source_id, :string
    field :source_name, :string
    field :vehicle_type, :string
    field :observed_at, :utc_datetime
    field :location, Hrafnsyn.GeometryType
    field :latitude, :float, virtual: true
    field :longitude, :float, virtual: true
    field :speed, :float
    field :heading, :float
    field :altitude, :integer
    field :payload, :map

    belongs_to :track, Hrafnsyn.Tracking.Track

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(point, attrs) do
    attrs = put_location(attrs)

    point
    |> cast(attrs, [
      :track_id,
      :source_id,
      :source_name,
      :vehicle_type,
      :observed_at,
      :location,
      :latitude,
      :longitude,
      :speed,
      :heading,
      :altitude,
      :payload
    ])
    |> validate_required([:track_id, :source_id, :source_name, :vehicle_type, :observed_at])
    |> unique_constraint([:track_id, :source_id, :observed_at])
  end

  defp put_location(attrs) do
    latitude = Map.get(attrs, :latitude)
    longitude = Map.get(attrs, :longitude)

    case {latitude, longitude} do
      {lat, lon} when is_number(lat) and is_number(lon) ->
        Map.put(attrs, :location, %Point{coordinates: {lon * 1.0, lat * 1.0}, srid: 4326})

      _other ->
        attrs
    end
  end
end
