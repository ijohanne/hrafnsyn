defmodule Hrafnsyn.DevicesTest do
  use Hrafnsyn.DataCase, async: true
  import Hrafnsyn.AccountsFixtures
  import ExUnit.CaptureLog
  alias Hrafnsyn.Devices
  alias Hrafnsyn.Devices.Invitation

  @udid "00008110-00123456789ABCDE"
  @other_udid "00008120-00123456789ABCDE"

  setup do
    %{scope: user_scope_fixture(), other_scope: user_scope_fixture()}
  end

  test "only the owning account can list, copy, revoke or delete an invitation", context do
    %{scope: scope, other_scope: other} = context
    assert {:ok, invitation} = Devices.create_invitation(scope, %{label: "  Alex's iPad  "})
    assert invitation.label == "Alex's iPad"
    assert [listed] = Devices.list_invitations(scope)
    assert listed.id == invitation.id
    assert {:ok, listed.share_token} == Devices.invitation_token(scope, invitation.id)
    assert [] == Devices.list_invitations(other)
    assert [] == Devices.list_invitations(nil)
    assert {:error, :not_found} = Devices.invitation_token(other, invitation.id)
    assert {:error, :not_found} = Devices.revoke_invitation(other, invitation.id)
    assert {:error, :not_found} = Devices.delete_invitation(other, invitation.id)
    assert {:error, :unauthorized} = Devices.create_invitation(nil, %{label: "Alex"})
    assert {:error, :not_found} = Devices.delete_invitation(scope, "malformed")
    assert {:ok, _} = Devices.delete_invitation(scope, invitation.id)
    assert [] == Devices.list_invitations(scope)
  end

  test "links survive a reload without persisting bearer tokens", %{scope: scope} do
    {invitation, token, challenge} = invitation(scope)
    assert {:ok, ^token} = Devices.invitation_token(scope, invitation.id)
    assert byte_size(token) == 80
    assert byte_size(challenge) == 43
    assert invitation.token_hash == :crypto.hash(:sha256, token)
    assert invitation.challenge_hash == :crypto.hash(:sha256, challenge)
    refute challenge == String.split(token, ".") |> List.last()
    assert {:ok, %{invitation_id: id, challenge: ^challenge}} = Devices.get_profile(token)
    assert id == invitation.id
    assert {:error, :not_found} = Devices.get_public_invitation(token <> "x")
    assert {:error, :not_found} = Devices.get_public_invitation(String.duplicate("a", 80))
    assert {:error, :not_found} = Devices.get_public_invitation(nil)
  end

  test "public pages disclose the recipient but never the collected UDID", %{scope: scope} do
    {invitation, token, challenge} = invitation(scope)
    assert {:ok, pending} = Devices.get_public_invitation(token)
    assert pending.status == :pending
    assert pending.owner_name == scope.user.username
    refute Map.has_key?(pending, :udid)
    refute Map.has_key?(pending, :user_id)
    assert {:ok, :collected} = Devices.complete_invitation(token, challenge, @udid)
    assert {:ok, ^challenge} = Devices.profile_challenge(token)
    assert {:ok, received} = Devices.get_public_invitation(token)
    assert received.status == :collected
    refute Map.has_key?(received, :udid)
    assert [%Invitation{id: id, udid: @udid}] = Devices.list_invitations(scope)
    assert id == invitation.id
    assert {:error, :unavailable} = Devices.get_profile(token)
  end

  test "consumption is idempotent for the same device but cannot overwrite a result", %{
    scope: scope
  } do
    {_invitation, token, challenge} = invitation(scope)

    assert {:ok, :collected} =
             Devices.complete_invitation(token, challenge, String.downcase(@udid))

    assert {:ok, :collected} = Devices.complete_invitation(token, challenge, @udid)

    assert {:error, :already_collected} =
             Devices.complete_invitation(token, challenge, @other_udid)

    assert [%Invitation{udid: @udid}] = Devices.list_invitations(scope)
  end

  test "a profile challenge cannot be reused with another invitation", %{scope: scope} do
    {_first, token, challenge} = invitation(scope)
    {_second, other_token, other_challenge} = invitation(scope)

    assert {:error, :invalid_submission} =
             Devices.complete_invitation(token, other_challenge, @udid)

    assert {:error, :invalid_submission} =
             Devices.complete_invitation(other_token, challenge, @udid)

    assert {:error, :invalid_submission} = Devices.complete_invitation(token, nil, @udid)

    assert {:error, :invalid_submission} =
             Devices.complete_invitation(token, challenge, "not-a-device")

    assert {:error, :invalid_submission} =
             Devices.complete_invitation(token, challenge, String.duplicate("a", 41))

    assert {:ok, %{status: :pending}} = Devices.get_public_invitation(token)

    assert {:ok, :collected} =
             Devices.complete_invitation(token, challenge, String.duplicate("b", 40))
  end

  test "expiry and revocation prevent profile generation and collection", %{scope: scope} do
    {invitation, token, challenge} = invitation(scope)
    assert {:ok, _} = Devices.revoke_invitation(scope, invitation.id)
    assert {:ok, %{status: :revoked}} = Devices.get_public_invitation(token)
    assert {:error, :unavailable} = Devices.get_profile(token)
    assert {:error, :invalid_submission} = Devices.complete_invitation(token, challenge, @udid)

    {expired, expired_token, expired_challenge} = invitation(scope)

    Repo.update_all(from(i in Invitation, where: i.id == ^expired.id),
      set: [expires_at: DateTime.utc_now(:second)]
    )

    assert {:ok, %{status: :expired}} = Devices.get_public_invitation(expired_token)
    assert {:error, :unavailable} = Devices.get_profile(expired_token)

    assert {:error, :invalid_submission} =
             Devices.complete_invitation(expired_token, expired_challenge, @udid)
  end

  test "quota includes collected, revoked and expired links until deletion", %{scope: scope} do
    {first, token, challenge} = invitation(scope)
    assert {:ok, :collected} = Devices.complete_invitation(token, challenge, @udid)
    assert {:ok, _} = Devices.revoke_invitation(scope, first.id)
    for _ <- 1..24, do: assert({:ok, _} = Devices.create_invitation(scope, %{label: "Friend"}))
    assert {:error, :limit_reached} = Devices.create_invitation(scope, %{label: "Over limit"})
    assert length(Devices.list_invitations(scope)) == 25

    Repo.update_all(from(i in Invitation, where: i.id == ^first.id),
      set: [expires_at: DateTime.utc_now(:second)]
    )

    assert {:error, :limit_reached} = Devices.create_invitation(scope, %{label: "New week"})
    assert {:ok, _} = Devices.delete_invitation(scope, first.id)
    assert {:ok, _} = Devices.create_invitation(scope, %{label: "New invitation"})
  end

  test "listing or creating prunes only the owner's records older than 30 days", context do
    %{scope: scope, other_scope: other} = context
    {old, old_token, _} = invitation(scope)
    {others_old, _, _} = invitation(other)
    cutoff = DateTime.add(DateTime.utc_now(:second), -31 * 24 * 60 * 60)

    Repo.update_all(from(i in Invitation, where: i.id in ^[old.id, others_old.id]),
      set: [inserted_at: cutoff]
    )

    assert [] == Devices.list_invitations(scope)
    assert {:error, :not_found} = Devices.get_public_invitation(old_token)
    assert Repo.get(Invitation, others_old.id)
    assert {:ok, _} = Devices.create_invitation(other, %{label: "Current"})
    refute Repo.get(Invitation, others_old.id)
  end

  test "deleted accounts cannot create and cascading deletion removes results", %{scope: scope} do
    {_invitation, token, _} = invitation(scope)
    Repo.delete!(scope.user)
    assert {:error, :unauthorized} = Devices.create_invitation(scope, %{label: "Deleted account"})
    assert {:error, :not_found} = Devices.get_public_invitation(token)
  end

  test "scheduled retention removes old collected identifiers even for inactive owners",
       context do
    %{scope: scope, other_scope: other} = context
    {old, token, challenge} = invitation(scope)
    assert {:ok, :collected} = Devices.complete_invitation(token, challenge, @udid)
    {also_old, _, _} = invitation(other)
    {current, _, _} = invitation(scope)
    cutoff = DateTime.add(DateTime.utc_now(:second), -31 * 24 * 60 * 60)

    Repo.update_all(from(i in Invitation, where: i.id in ^[old.id, also_old.id]),
      set: [inserted_at: cutoff]
    )

    assert 2 == Devices.prune_expired_invitations()
    refute Repo.get(Invitation, old.id)
    refute Repo.get(Invitation, also_old.id)
    assert Repo.get(Invitation, current.id)
    assert 0 == Devices.prune_expired_invitations()
  end

  test "invalid labels and supplied ownership or collection fields are rejected or ignored",
       context do
    %{scope: scope, other_scope: other} = context
    assert {:error, changeset} = Devices.create_invitation(scope, %{label: " "})
    assert "can't be blank" in errors_on(changeset).label
    assert {:error, _} = Devices.create_invitation(scope, %{label: String.duplicate("a", 81)})

    assert {:ok, result} =
             Devices.create_invitation(scope, %{
               label: "My phone",
               user_id: other.user.id,
               udid: @udid,
               expires_at: DateTime.add(DateTime.utc_now(:second), 1_000_000)
             })

    assert result.user_id == scope.user.id
    assert is_nil(result.udid)
    assert DateTime.diff(result.expires_at, result.inserted_at) == 7 * 24 * 60 * 60
  end

  test "identifier and bearer material are redacted from schema inspection and Ecto logs", %{
    scope: scope
  } do
    {invitation, token, challenge} = invitation(scope)

    log =
      capture_log(fn ->
        assert {:ok, :collected} = Devices.complete_invitation(token, challenge, @udid)
        assert [_] = Devices.list_invitations(scope)
      end)

    refute log =~ @udid
    refute log =~ token
    refute log =~ challenge
    stored = Repo.get!(Invitation, invitation.id, log: false)
    refute inspect(stored) =~ @udid
    refute inspect(stored) =~ "udid:"
  end

  defp invitation(scope) do
    {:ok, invitation} = Devices.create_invitation(scope, %{label: "Friend's device"})
    {:ok, token} = Devices.invitation_token(scope, invitation.id)
    {:ok, challenge} = Devices.profile_challenge(token)
    {invitation, token, challenge}
  end
end
