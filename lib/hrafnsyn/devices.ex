defmodule Hrafnsyn.Devices do
  @moduledoc "Account-scoped, expiring invitations for collecting iOS device identifiers."
  import Ecto.Query
  alias Ecto.Changeset
  alias Hrafnsyn.Accounts.{Scope, User}
  alias Hrafnsyn.Devices.Invitation
  alias Hrafnsyn.Repo

  @lifetime_seconds 7 * 24 * 60 * 60
  @retention_seconds 30 * 24 * 60 * 60
  @saved_limit 25

  def change_invitation(invitation \\ %Invitation{}, attrs \\ %{}),
    do: Invitation.changeset(invitation, attrs)

  def list_invitations(%Scope{user: %User{id: user_id}}) when is_binary(user_id) do
    prune_owner(user_id)

    Repo.all(
      from(i in Invitation,
        where: i.user_id == ^user_id,
        order_by: [desc: i.inserted_at, desc: i.id]
      ),
      log: false
    )
    |> Enum.map(&%{&1 | share_token: token(&1.id)})
  end

  def list_invitations(_scope), do: []

  def prune_expired_invitations do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@retention_seconds)

    {deleted, _} =
      Repo.delete_all(from(i in Invitation, where: i.inserted_at < ^cutoff), log: false)

    deleted
  end

  def create_invitation(%Scope{user: %User{id: user_id}}, attrs)
      when is_binary(user_id) and is_map(attrs) do
    Repo.transaction(
      fn ->
        # Serialize account-wide quota checks, including concurrent browser tabs.
        unless Repo.one(from(u in User, where: u.id == ^user_id, lock: "FOR UPDATE"), log: false),
          do: Repo.rollback(:unauthorized)

        prune_owner(user_id)
        now = DateTime.utc_now(:second)

        count =
          Repo.aggregate(
            from(i in Invitation, where: i.user_id == ^user_id),
            :count,
            log: false
          )

        if count >= @saved_limit, do: Repo.rollback(:limit_reached)

        id = Ecto.UUID.generate()

        %Invitation{id: id}
        |> Invitation.changeset(attrs)
        |> Changeset.put_change(:user_id, user_id)
        |> Changeset.put_change(:expires_at, DateTime.add(now, @lifetime_seconds))
        |> Changeset.put_change(:token_hash, digest(token(id)))
        |> Changeset.put_change(:challenge_hash, digest(challenge(id)))
        |> Repo.insert(log: false)
        |> unwrap_transaction()
      end,
      log: false
    )
  end

  def create_invitation(_scope, _attrs), do: {:error, :unauthorized}

  def invitation_token(scope, id) do
    with {:ok, invitation} <- owned_invitation(scope, id) do
      {:ok, token(invitation.id)}
    end
  end

  def get_public_invitation(token) do
    with {:ok, token_hash} <- token_digest(token),
         summary when not is_nil(summary) <-
           Repo.one(
             from(i in Invitation,
               join: u in User,
               on: u.id == i.user_id,
               where: i.token_hash == ^token_hash,
               select: %{
                 id: i.id,
                 label: i.label,
                 owner_name: u.username,
                 expires_at: i.expires_at,
                 collected_at: i.collected_at,
                 revoked_at: i.revoked_at
               }
             ),
             log: false
           ) do
      {:ok, Map.put(summary, :status, invitation_status(summary))}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_profile(token) do
    case get_public_invitation(token) do
      {:ok, %{status: :pending, id: id}} ->
        {:ok, %{invitation_id: id, challenge: challenge(id)}}

      {:ok, _summary} ->
        {:error, :unavailable}

      error ->
        error
    end
  end

  def profile_challenge(token) do
    case get_public_invitation(token) do
      {:ok, %{status: status, id: id}} when status in [:pending, :collected] ->
        {:ok, challenge(id)}

      {:ok, _summary} ->
        {:error, :unavailable}

      error ->
        error
    end
  end

  def complete_invitation(token, challenge, udid) do
    with {:ok, token_hash} <- token_digest(token),
         true <- is_binary(challenge) and byte_size(challenge) == 43,
         %{valid?: true} = changeset <-
           Invitation.collection_changeset(%Invitation{}, %{udid: udid}) do
      normalized_udid = Changeset.get_field(changeset, :udid)
      challenge_hash = digest(challenge)

      Repo.transaction(
        fn ->
          invitation =
            Repo.one(
              from(i in Invitation, where: i.token_hash == ^token_hash, lock: "FOR UPDATE"),
              log: false
            )

          consume(invitation, challenge_hash, normalized_udid)
        end,
        log: false
      )
    else
      _ -> {:error, :invalid_submission}
    end
  end

  def revoke_invitation(scope, id) do
    with {:ok, invitation} <- owned_invitation(scope, id) do
      invitation
      |> Changeset.change(revoked_at: invitation.revoked_at || DateTime.utc_now(:second))
      |> Repo.update(log: false)
    end
  end

  def delete_invitation(scope, id) do
    with {:ok, invitation} <- owned_invitation(scope, id) do
      Repo.delete(invitation, log: false)
    end
  end

  def invitation_status(%{revoked_at: revoked_at}) when not is_nil(revoked_at), do: :revoked

  def invitation_status(%{expires_at: expires_at, collected_at: collected_at}) do
    cond do
      DateTime.compare(expires_at, DateTime.utc_now(:second)) != :gt -> :expired
      not is_nil(collected_at) -> :collected
      true -> :pending
    end
  end

  defp consume(nil, _challenge_hash, _udid), do: Repo.rollback(:invalid_submission)

  defp consume(invitation, challenge_hash, udid) do
    if not Plug.Crypto.secure_compare(invitation.challenge_hash, challenge_hash) or
         invitation_status(invitation) in [:expired, :revoked],
       do: Repo.rollback(:invalid_submission)

    case invitation do
      %{udid: ^udid} ->
        :collected

      %{udid: nil} ->
        invitation
        |> Changeset.change(udid: udid, collected_at: DateTime.utc_now(:second))
        |> Repo.update(log: false)
        |> unwrap_transaction()

        :collected

      _ ->
        Repo.rollback(:already_collected)
    end
  end

  defp owned_invitation(%Scope{user: %User{id: user_id}}, id) when is_binary(user_id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Invitation{} = invitation <-
           Repo.one(from(i in Invitation, where: i.id == ^id and i.user_id == ^user_id),
             log: false
           ) do
      {:ok, invitation}
    else
      _ -> {:error, :not_found}
    end
  end

  defp owned_invitation(_scope, _id), do: {:error, :unauthorized}

  defp prune_owner(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@retention_seconds)

    Repo.delete_all(
      from(i in Invitation, where: i.user_id == ^user_id and i.inserted_at < ^cutoff),
      log: false
    )
  end

  defp token(id), do: id <> "." <> mac("invitation", id)
  defp challenge(id), do: mac("profile-challenge", id)

  defp mac(purpose, id) do
    secret = HrafnsynWeb.Endpoint.config(:secret_key_base)

    :crypto.mac(:hmac, :sha256, secret, "hrafnsyn-device-" <> purpose <> ":v1:" <> id)
    |> Base.url_encode64(padding: false)
  end

  defp token_digest(token) when is_binary(token) and byte_size(token) == 80,
    do: {:ok, digest(token)}

  defp token_digest(_token), do: {:error, :not_found}
  defp digest(value), do: :crypto.hash(:sha256, value)
  defp unwrap_transaction({:ok, value}), do: value
  defp unwrap_transaction({:error, error}), do: Repo.rollback(error)
end
