defmodule Hrafnsyn.Accounts.ApiSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "api_sessions" do
    field :name, :string
    field :refresh_token_hash, :binary
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, Hrafnsyn.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :id,
      :user_id,
      :name,
      :refresh_token_hash,
      :last_used_at,
      :expires_at,
      :revoked_at
    ])
    |> normalize_name()
    |> validate_length(:name, min: 1, max: 80)
    |> validate_required([:id, :user_id, :refresh_token_hash, :expires_at])
    |> foreign_key_constraint(:user_id)
  end

  def create_changeset(session, attrs) do
    session
    |> changeset(attrs)
    |> validate_required([:name])
  end

  def rename_changeset(session, attrs) do
    session
    |> cast(attrs, [:name])
    |> normalize_name()
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
  end

  defp normalize_name(changeset) do
    update_change(changeset, :name, &String.trim/1)
  end
end
