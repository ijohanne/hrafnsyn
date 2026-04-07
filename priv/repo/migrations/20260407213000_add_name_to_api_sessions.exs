defmodule Hrafnsyn.Repo.Migrations.AddNameToApiSessions do
  use Ecto.Migration

  def change do
    alter table(:api_sessions) do
      add :name, :string
    end
  end
end
