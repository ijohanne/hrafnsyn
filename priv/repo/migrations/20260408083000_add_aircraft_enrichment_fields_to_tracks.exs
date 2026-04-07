defmodule Hrafnsyn.Repo.Migrations.AddAircraftEnrichmentFieldsToTracks do
  use Ecto.Migration

  def change do
    alter table(:tracks) do
      add :aircraft_type, :string
      add :type_description, :string
      add :wake_turbulence_category, :string
    end
  end
end
