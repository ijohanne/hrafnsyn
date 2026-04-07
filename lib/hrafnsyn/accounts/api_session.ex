defmodule Hrafnsyn.Accounts.ApiSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "api_sessions" do
    field :refresh_token_hash, :binary
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, Hrafnsyn.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:id, :user_id, :refresh_token_hash, :last_used_at, :expires_at, :revoked_at])
    |> validate_required([:id, :user_id, :refresh_token_hash, :expires_at])
    |> foreign_key_constraint(:user_id)
  end
end
