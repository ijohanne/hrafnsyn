defmodule Hrafnsyn.Accounts.ApiAuthState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:name, :string, autogenerate: false}

  schema "api_auth_states" do
    field :global_revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:name, :global_revoked_at])
    |> validate_required([:name])
  end
end
