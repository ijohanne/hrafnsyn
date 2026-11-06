defmodule HrafnsynWeb.DeviceControllerTest do
  use HrafnsynWeb.ConnCase, async: true

  import Hrafnsyn.AccountsFixtures
  import Hrafnsyn.DeviceProfileFixtures
  import ExUnit.CaptureLog

  alias Hrafnsyn.Accounts.Scope
  alias Hrafnsyn.Devices

  @udid "00008110-000123456789ABCD"

  test "management requires a signed-in account", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/users/devices")) == ~p"/users/log-in"
  end

  describe "owner management" do
    setup :register_and_log_in_user

    test "creates a private, reusable share link and shows the result only to its owner", %{
      conn: conn,
      scope: scope
    } do
      response = post(conn, ~p"/users/devices", invitation: %{label: "Friend’s iPad"})
      assert redirected_to(response) == ~p"/users/devices"
      [invitation] = Devices.list_invitations(scope)
      token = invitation.share_token
      assert html_response(get(conn, ~p"/users/devices"), 200) =~ token

      {:ok, challenge} = Devices.profile_challenge(token)
      assert {:ok, :collected} = Devices.complete_invitation(token, challenge, @udid)
      assert html_response(get(conn, ~p"/users/devices"), 200) =~ @udid

      other = build_conn() |> log_in_user(user_fixture()) |> get(~p"/users/devices")
      refute html_response(other, 200) =~ @udid
      refute other.resp_body =~ token
    end

    test "validates names without creating an invitation", %{conn: conn, scope: scope} do
      response = post(conn, ~p"/users/devices", invitation: %{label: ""})
      assert html_response(response, 422) =~ "Device label"
      assert Devices.list_invitations(scope) == []
    end

    test "cannot delete another account's invitation", %{conn: conn} do
      other = Scope.for_user(user_fixture())
      {:ok, invitation} = Devices.create_invitation(other, %{label: "Other device"})
      post(conn, ~p"/users/devices/#{invitation.id}/delete")
      assert [%{id: id}] = Devices.list_invitations(other)
      assert id == invitation.id
    end

    test "deleting removes the invitation and closes its public link", %{conn: conn, scope: scope} do
      {:ok, invitation} = Devices.create_invitation(scope, %{label: "Temporary device"})
      {:ok, token} = Devices.invitation_token(scope, invitation.id)
      post(conn, ~p"/users/devices/#{invitation.id}/delete")
      assert Devices.list_invitations(scope) == []
      assert html_response(get(build_conn(), ~p"/devices/invite/#{token}"), 404) =~ "unavailable"
    end

    test "management forms still enforce CSRF", %{conn: conn} do
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        conn
        |> put_private(:plug_skip_csrf_protection, false)
        |> post(~p"/users/devices", invitation: %{label: "Unapproved request"})
      end
    end
  end

  describe "public profile service" do
    setup do
      owner = user_fixture()
      scope = Scope.for_user(owner)
      {:ok, invitation} = Devices.create_invitation(scope, %{label: "Friend’s iPhone"})
      {:ok, token} = Devices.invitation_token(scope, invitation.id)
      {:ok, challenge} = Devices.profile_challenge(token)
      %{scope: scope, token: token, challenge: challenge, owner: owner}
    end

    test "explains collection without requiring a login and prevents caching/referrer leakage", %{
      conn: conn,
      token: token,
      owner: owner
    } do
      response = get(conn, ~p"/devices/invite/#{token}")
      html = html_response(response, 200)
      assert html =~ "Share your device identifier"
      assert html =~ owner.username
      assert html =~ "Not Signed"
      assert get_resp_header(response, "cache-control") == ["no-store"]
      assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
      assert get_resp_header(response, "x-robots-tag") == ["noindex, nofollow, noarchive"]
    end

    test "profile requests only UDID and derives its callback from configuration, not Host", %{
      conn: conn,
      token: token,
      challenge: challenge
    } do
      response = get(%{conn | host: "attacker.example"}, ~p"/devices/invite/#{token}/profile")
      assert response.status == 200
      assert response.resp_body =~ "<string>UDID</string>"
      assert response.resp_body =~ challenge
      assert response.resp_body =~ HrafnsynWeb.Endpoint.url()
      refute response.resp_body =~ "attacker.example"
      refute response.resp_body =~ "<string>SERIAL</string>"
      refute response.resp_body =~ "<string>IMEI</string>"
      assert [type] = get_resp_header(response, "content-type")
      assert type =~ "application/x-apple-aspen-config"
    end

    test "accepts a CMS callback without cookies/CSRF, redirects without UDID, and is idempotent",
         %{token: token, challenge: challenge} do
      body = callback(@udid, challenge)
      response = submit(token, body)
      assert response.status == 301

      assert get_resp_header(response, "location") == [
               HrafnsynWeb.Endpoint.url() <> ~p"/devices/invite/#{token}"
             ]

      refute hd(get_resp_header(response, "location")) =~ @udid
      assert submit(token, body).status == 301
      html = html_response(get(build_conn(), ~p"/devices/invite/#{token}"), 200)
      assert html =~ "Device identifier received"
      refute html =~ @udid
      assert get(build_conn(), ~p"/devices/invite/#{token}/profile").status == 404
    end

    test "accepts Apple's BER callback encoding", %{token: token, challenge: challenge} do
      # Preserve the Apple encoder's structure while binding the synthetic fixture
      # to this invitation; collection does not verify signer trust or signatures.
      body =
        "test/fixtures/devices/callback-apple.ber"
        |> File.read!()
        |> :binary.replace("j5mw3dSgkbUN31Pp9WqHVmAJ4OeDdYNqQHCHsi2ePlI", challenge)

      assert submit(token, body).status == 301
      assert {:ok, %{status: :collected}} = Devices.get_public_invitation(token)
    end

    test "logs only a fixed rejection category, without the invitation or response", %{
      token: token
    } do
      log =
        capture_log(fn ->
          assert submit(token, "private-device-response-sentinel").status == 400
        end)

      assert log =~ "Device profile callback rejected: invalid_cms"
      refute log =~ token
      refute log =~ "private-device-response-sentinel"
    end

    test "rejects a wrong challenge and cannot overwrite a completed identifier", %{
      token: token,
      challenge: challenge
    } do
      assert submit(token, callback(@udid, "wrong challenge")).status == 400
      assert submit(token, callback(@udid, challenge)).status == 301
      assert submit(token, callback("00008110-000123456789ABCE", challenge)).status == 400
    end

    test "rejects oversized and incorrectly typed uploads before general parsers", %{token: token} do
      assert submit(token, String.duplicate("x", 65_537)).status == 413

      response =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/devices/invite/#{token}/callback", "{}")

      assert response.status == 415
      assert submit(token, "not CMS").status == 400
    end

    test "invalid links are generic and not cached", %{conn: conn} do
      response = get(conn, ~p"/devices/invite/invalid")
      assert html_response(response, 404) =~ "unavailable"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    test "public bearer paths disable standard request logging", %{conn: conn} do
      assert HrafnsynWeb.Endpoint.request_log_level(%{
               conn
               | path_info: ["devices", "invite", "secret"]
             }) == false

      assert HrafnsynWeb.Endpoint.request_log_level(%{conn | path_info: ["users", "devices"]}) ==
               :info
    end
  end

  defp submit(token, body) do
    build_conn()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("content-type", "application/pkcs7-signature")
    |> post(~p"/devices/invite/#{token}/callback", body)
  end
end
