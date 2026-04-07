defmodule Hrafnsyn.Tracking.TrackPoint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "track_points" do
    field :source_id, :string
    field :source_name, :string
    field :vehicle_type, :string
    field :observed_at, :utc_datetime
    field :latitude, :float
    field :longitude, :float
    field :speed, :float
    field :heading, :float
    field :altitude, :integer
    field :payload, :map

    belongs_to :track, Hrafnsyn.Tracking.Track

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(point, attrs) do
    point
    |> cast(attrs, [
      :track_id,
      :source_id,
      :source_name,
      :vehicle_type,
      :observed_at,
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
end
