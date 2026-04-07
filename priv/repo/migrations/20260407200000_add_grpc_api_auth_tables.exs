defmodule Hrafnsyn.Repo.Migrations.AddGrpcApiAuthTables do
  use Ecto.Migration

  def change do
    create table(:api_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :refresh_token_hash, :binary, null: false
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:api_sessions, [:user_id])
    create index(:api_sessions, [:expires_at])

    create table(:api_auth_states, primary_key: false) do
      add :name, :string, primary_key: true
      add :global_revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end
end
