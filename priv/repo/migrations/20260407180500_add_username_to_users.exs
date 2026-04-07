defmodule Hrafnsyn.Repo.Migrations.AddUsernameToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :username, :citext
      modify :email, :citext, null: true
    end

    execute("""
    UPDATE users
    SET username = email
    WHERE username IS NULL
    """)

    alter table(:users) do
      modify :username, :citext, null: false
    end

    create unique_index(:users, [:username])
  end

  def down do
    drop_if_exists unique_index(:users, [:username])

    alter table(:users) do
      remove :username
      modify :email, :citext, null: false
    end
  end
end
