defmodule Hrafnsyn.Repo.Migrations.ConvertTrackingToPostgis do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS postgis", "DROP EXTENSION IF EXISTS postgis"

    execute "ALTER TABLE tracks ADD COLUMN location geography(Point, 4326)", "ALTER TABLE tracks DROP COLUMN location"
    execute "ALTER TABLE track_points ADD COLUMN location geography(Point, 4326)", "ALTER TABLE track_points DROP COLUMN location"

    execute """
    UPDATE tracks
    SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
    """, ""

    execute """
    UPDATE track_points
    SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
    """, ""

    execute "CREATE INDEX tracks_location_gist_idx ON tracks USING gist (location)", "DROP INDEX IF EXISTS tracks_location_gist_idx"
    execute "CREATE INDEX track_points_location_gist_idx ON track_points USING gist (location)", "DROP INDEX IF EXISTS track_points_location_gist_idx"

    alter table(:tracks) do
      remove :latitude
      remove :longitude
    end

    alter table(:track_points) do
      remove :latitude
      remove :longitude
    end
  end

  def down do
    alter table(:tracks) do
      add :latitude, :float
      add :longitude, :float
    end

    alter table(:track_points) do
      add :latitude, :float
      add :longitude, :float
    end

    execute """
    UPDATE tracks
    SET latitude = ST_Y(location::geometry),
        longitude = ST_X(location::geometry)
    WHERE location IS NOT NULL
    """, ""

    execute """
    UPDATE track_points
    SET latitude = ST_Y(location::geometry),
        longitude = ST_X(location::geometry)
    WHERE location IS NOT NULL
    """, ""

    execute "DROP INDEX IF EXISTS track_points_location_gist_idx", ""
    execute "DROP INDEX IF EXISTS tracks_location_gist_idx", ""

    execute "ALTER TABLE track_points DROP COLUMN location", ""
    execute "ALTER TABLE tracks DROP COLUMN location", ""
  end
end
