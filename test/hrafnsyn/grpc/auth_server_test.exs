defmodule Hrafnsyn.GRPC.AuthServerTest do
  use Hrafnsyn.DataCase

  import GRPC.RPCError, only: [is_rpc_error: 2]
  import Hrafnsyn.AccountsFixtures

  alias Hrafnsyn.Accounts
  alias Hrafnsyn.Accounts.ApiSession
  alias Hrafnsyn.V1.AuthService.Stub, as: AuthStub
  alias Hrafnsyn.V1.TrackingService.Stub, as: TrackingStub

  @permission_denied GRPC.Status.permission_denied()
  @unauthenticated GRPC.Status.unauthenticated()

  describe "gRPC auth flows" do
    test "supports login in auth-required mode and rejects anonymous tracking calls" do
      user = user_fixture() |> set_password()
      put_public_readonly(false)
      channel = grpc_channel!()

      assert {:ok, %Hrafnsyn.V1.AuthStatus{auth_required: true, authenticated: false}} =
               AuthStub.get_auth_status(channel, %Google.Protobuf.Empty{})

      assert {:error, error} =
               TrackingStub.get_system_info(channel, %Google.Protobuf.Empty{})

      assert is_rpc_error(error, @unauthenticated)

      assert {:error, error} =
               AuthStub.login(channel, %Hrafnsyn.V1.LoginRequest{
                 username: user.username,
                 password: "invalid-password"
               })

      assert is_rpc_error(error, @unauthenticated)

      assert {:ok, %Hrafnsyn.V1.TokenPair{access_token: access_token, refresh_token: refresh_token}} =
               AuthStub.login(channel, %Hrafnsyn.V1.LoginRequest{
                 username: user.username,
                 password: valid_user_password()
               })

      assert access_token != ""
      assert refresh_token != ""

      assert {:ok, %Hrafnsyn.V1.SystemInfo{counts: %Hrafnsyn.V1.ActiveCounts{total: 0}}} =
               TrackingStub.get_system_info(
                 channel,
                 %Google.Protobuf.Empty{},
                 metadata: auth_metadata(access_token)
               )
    end

    test "rotates refresh tokens and rejects expired sessions" do
      user = user_fixture() |> set_password()
      put_public_readonly(false)
      channel = grpc_channel!()

      assert {:ok, login} =
               AuthStub.login(channel, %Hrafnsyn.V1.LoginRequest{
                 username: user.username,
                 password: valid_user_password()
               })

      assert {:ok, refreshed} =
               AuthStub.refresh(
                 channel,
                 %Hrafnsyn.V1.RefreshRequest{refresh_token: login.refresh_token}
               )

      assert refreshed.access_token != login.access_token
      assert refreshed.refresh_token != login.refresh_token

      Repo.update_all(
        from(session in ApiSession, where: session.id == ^refreshed.session.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -5, :second)]
      )

      assert {:error, error} =
               AuthStub.refresh(
                 channel,
                 %Hrafnsyn.V1.RefreshRequest{refresh_token: refreshed.refresh_token}
               )

      assert is_rpc_error(error, @unauthenticated)
    end

    test "allows anonymous access in auth-optional mode even with an invalid bearer token" do
      put_public_readonly(true)
      channel = grpc_channel!()

      assert {:ok, %Hrafnsyn.V1.AuthStatus{auth_required: false, authenticated: false}} =
               AuthStub.get_auth_status(channel, %Google.Protobuf.Empty{})

      assert {:ok, %Hrafnsyn.V1.SystemInfo{counts: %Hrafnsyn.V1.ActiveCounts{total: 0}}} =
               TrackingStub.get_system_info(channel, %Google.Protobuf.Empty{})

      assert {:ok, %Hrafnsyn.V1.SystemInfo{counts: %Hrafnsyn.V1.ActiveCounts{total: 0}}} =
               TrackingStub.get_system_info(
                 channel,
                 %Google.Protobuf.Empty{},
                 metadata: auth_metadata("definitely-not-a-real-token")
               )
    end

    test "rejects access tokens after self revocation" do
      user = user_fixture() |> set_password()
      put_public_readonly(false)
      channel = grpc_channel!()

      assert {:ok, login} =
               AuthStub.login(channel, %Hrafnsyn.V1.LoginRequest{
                 username: user.username,
                 password: valid_user_password()
               })

      assert {:ok, %Hrafnsyn.V1.RevocationResponse{scope: "session"}} =
               AuthStub.revoke_session(
                 channel,
                 %Hrafnsyn.V1.RevokeSessionRequest{session_id: login.session.id},
                 metadata: auth_metadata(login.access_token)
               )

      assert {:error, error} =
               TrackingStub.get_system_info(
                 channel,
                 %Google.Protobuf.Empty{},
                 metadata: auth_metadata(login.access_token)
               )

      assert is_rpc_error(error, @unauthenticated)
    end

    test "lets admins revoke all sessions globally" do
      put_public_readonly(false)
      admin = admin_user_fixture()
      user = user_fixture() |> set_password()
      channel = grpc_channel!()

      assert {:ok, admin_login} =
               AuthStub.login(channel, %Hrafnsyn.V1.LoginRequest{
                 username: admin.username,
                 password: valid_user_password()
               })

      assert {:ok, user_login} =
               AuthStub.login(channel, %Hrafnsyn.V1.LoginRequest{
                 username: user.username,
                 password: valid_user_password()
               })

      assert {:ok, %Hrafnsyn.V1.RevocationResponse{scope: "global"}} =
               AuthStub.revoke_all_sessions(
                 channel,
                 %Google.Protobuf.Empty{},
                 metadata: auth_metadata(admin_login.access_token)
               )

      assert {:error, error} =
               TrackingStub.get_system_info(
                 channel,
                 %Google.Protobuf.Empty{},
                 metadata: auth_metadata(user_login.access_token)
               )

      assert is_rpc_error(error, @unauthenticated)
    end

    test "rejects global revocation for non-admin users" do
      put_public_readonly(false)
      user = user_fixture() |> set_password()
      channel = grpc_channel!()

      assert {:ok, login} =
               AuthStub.login(channel, %Hrafnsyn.V1.LoginRequest{
                 username: user.username,
                 password: valid_user_password()
               })

      assert {:error, error} =
               AuthStub.revoke_all_sessions(
                 channel,
                 %Google.Protobuf.Empty{},
                 metadata: auth_metadata(login.access_token)
               )

      assert is_rpc_error(error, @permission_denied)
    end
  end

  defp grpc_channel! do
    port = 55_000 + rem(System.unique_integer([:positive]), 1_000)

    ensure_grpc_client_supervisor!()

    start_supervised!(
      {GRPC.Server.Supervisor,
       endpoint: Hrafnsyn.GRPC.Endpoint,
       port: port,
       start_server: true,
       adapter_opts: [ip: {127, 0, 0, 1}]}
    )

    Process.sleep(50)

    {:ok, channel} = GRPC.Stub.connect("127.0.0.1:#{port}")
    channel
  end

  defp ensure_grpc_client_supervisor! do
    case Process.whereis(GRPC.Client.Supervisor) do
      nil ->
        start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: GRPC.Client.Supervisor})

      _pid ->
        :ok
    end
  end

  defp put_public_readonly(public_readonly?) do
    original_public_readonly = Application.get_env(:hrafnsyn, :public_readonly?, true)
    original_grpc_config = Application.get_env(:hrafnsyn, Hrafnsyn.GRPC, [])

    Application.put_env(:hrafnsyn, :public_readonly?, public_readonly?)
    Application.put_env(:hrafnsyn, Hrafnsyn.GRPC, Keyword.put(original_grpc_config, :jwt_secret, "test-grpc-secret"))

    on_exit(fn ->
      Application.put_env(:hrafnsyn, :public_readonly?, original_public_readonly)
      Application.put_env(:hrafnsyn, Hrafnsyn.GRPC, original_grpc_config)
    end)
  end

  defp auth_metadata(access_token) do
    %{"authorization" => "Bearer #{access_token}"}
  end

  defp admin_user_fixture do
    attrs =
      valid_user_attributes(%{
        password: valid_user_password(),
        is_admin: true
      })

    {:ok, user} = Accounts.create_user_by_admin(attrs)
    user
  end
end
