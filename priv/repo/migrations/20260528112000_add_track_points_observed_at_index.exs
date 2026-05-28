defmodule Hrafnsyn.Repo.Migrations.AddTrackPointsObservedAtIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS track_points_observed_at_idx
    ON track_points (observed_at)
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS track_points_observed_at_idx"
  end
end
