defmodule Hrafnsyn.Repo.Migrations.CreateDeviceInvitations do
  use Ecto.Migration

  def change do
    create table(:device_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :label, :string, size: 80, null: false
      add :token_hash, :binary, null: false
      add :challenge_hash, :binary, null: false
      add :udid, :string, size: 40
      add :expires_at, :utc_datetime, null: false
      add :collected_at, :utc_datetime
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:device_invitations, [:token_hash])
    create index(:device_invitations, [:user_id, :expires_at])
    create index(:device_invitations, [:user_id, :inserted_at])
    create index(:device_invitations, [:inserted_at])

    create constraint(:device_invitations, :device_collection_consistent,
             check: "(udid IS NULL) = (collected_at IS NULL)"
           )

    create constraint(:device_invitations, :device_hash_lengths,
             check: "octet_length(token_hash) = 32 AND octet_length(challenge_hash) = 32"
           )
  end
end
