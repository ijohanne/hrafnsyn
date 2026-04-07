defmodule Hrafnsyn.Repo.Migrations.CreateTrackingTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", ""

    create table(:tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_type, :string, null: false
      add :identity, :string, null: false
      add :latest_source_id, :string, null: false
      add :latest_source_name, :string, null: false
      add :display_name, :string
      add :callsign, :string
      add :registration, :string
      add :country, :string
      add :category, :string
      add :status, :string
      add :destination, :string
      add :latitude, :float
      add :longitude, :float
      add :speed, :float
      add :heading, :float
      add :altitude, :integer
      add :observed_at, :utc_datetime, null: false
      add :search_text, :text
      add :last_payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tracks, [:vehicle_type, :identity])
    create index(:tracks, [:observed_at])

    execute "CREATE INDEX tracks_search_text_trgm_idx ON tracks USING gin (search_text gin_trgm_ops)",
            ""

    create table(:track_points, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false
      add :source_id, :string, null: false
      add :source_name, :string, null: false
      add :vehicle_type, :string, null: false
      add :observed_at, :utc_datetime, null: false
      add :latitude, :float
      add :longitude, :float
      add :speed, :float
      add :heading, :float
      add :altitude, :integer
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:track_points, [:track_id, :observed_at])
    create unique_index(:track_points, [:track_id, :source_id, :observed_at])
  end
end
