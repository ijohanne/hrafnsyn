defmodule Hrafnsyn.Tracking.Track do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tracks" do
    field :vehicle_type, :string
    field :identity, :string
    field :latest_source_id, :string
    field :latest_source_name, :string
    field :display_name, :string
    field :callsign, :string
    field :registration, :string
    field :country, :string
    field :category, :string
    field :status, :string
    field :destination, :string
    field :latitude, :float
    field :longitude, :float
    field :speed, :float
    field :heading, :float
    field :altitude, :integer
    field :observed_at, :utc_datetime
    field :search_text, :string
    field :last_payload, :map

    has_many :points, Hrafnsyn.Tracking.TrackPoint

    timestamps(type: :utc_datetime)
  end

  def derive_search_text(attrs), do: build_search_text(attrs)

  def changeset(track, attrs) do
    attrs = Map.put(attrs, :search_text, build_search_text(attrs))

    track
    |> cast(attrs, [
      :vehicle_type,
      :identity,
      :latest_source_id,
      :latest_source_name,
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
      :search_text,
      :last_payload
    ])
    |> validate_required([
      :vehicle_type,
      :identity,
      :latest_source_id,
      :latest_source_name,
      :observed_at
    ])
    |> unique_constraint([:vehicle_type, :identity])
  end

  defp build_search_text(attrs) do
    attrs
    |> Map.take([:identity, :display_name, :callsign, :registration, :destination, :country])
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
