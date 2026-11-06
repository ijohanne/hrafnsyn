defmodule Hrafnsyn.Devices.Invitation do
  @moduledoc "A one-device collection invitation belonging to one account."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @udid_format ~r/\A(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})\z/

  schema "device_invitations" do
    field :label, :string
    field :token_hash, :binary, redact: true
    field :challenge_hash, :binary, redact: true
    field :share_token, :string, virtual: true, redact: true
    field :udid, :string, redact: true
    field :expires_at, :utc_datetime
    field :collected_at, :utc_datetime
    field :revoked_at, :utc_datetime
    belongs_to :user, Hrafnsyn.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:label])
    |> update_change(:label, &String.trim/1)
    |> validate_required([:label])
    |> validate_length(:label, max: 80)
    |> validate_format(:label, ~r/\A[^\x00-\x1f\x7f]+\z/u)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token_hash)
  end

  def collection_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:udid])
    |> validate_required([:udid])
    |> validate_format(:udid, @udid_format)
    |> update_change(:udid, &String.upcase/1)
  end
end
