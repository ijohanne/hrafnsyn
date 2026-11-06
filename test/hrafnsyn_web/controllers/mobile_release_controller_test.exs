defmodule HrafnsynWeb.MobileReleaseControllerTest do
  use HrafnsynWeb.ConnCase, async: false

  import Hrafnsyn.AccountsFixtures

  alias Hrafnsyn.{Accounts, Devices, MobileBuilds}
  alias Hrafnsyn.Accounts.{ApiAuth, Scope}

  setup do
    directory = Path.join(System.tmp_dir!(), "hrafnsyn-release-web-#{Ecto.UUID.generate()}")
    previous = Application.fetch_env(:hrafnsyn, :mobile_build_directory)
    Application.put_env(:hrafnsyn, :mobile_build_directory, directory)

    on_exit(fn ->
      File.rm_rf!(directory)

      case previous do
        {:ok, value} -> Application.put_env(:hrafnsyn, :mobile_build_directory, value)
        :error -> Application.delete_env(:hrafnsyn, :mobile_build_directory)
      end
    end)

    {:ok, admin} =
      Accounts.create_user_by_admin(%{
        username: unique_user_username(),
        password: valid_user_password(),
        is_admin: true
      })

    {:ok, tokens} = ApiAuth.issue_token_pair(admin)
    %{directory: directory, admin: admin, tokens: tokens, member: user_fixture()}
  end

  test "refresh rotates a token pair without a browser session", %{tokens: tokens} do
    response = bearer(tokens.refresh_token) |> post(~p"/api/mobile-release/session")
    pair = json_response(response, 200)
    assert pair["access_token"] != tokens.access_token
    assert pair["refresh_token"] != tokens.refresh_token
    assert {:ok, _context} = ApiAuth.authenticate_access_token(pair["access_token"])
    assert get_resp_header(response, "cache-control") == ["no-store"]

    reused = bearer(tokens.refresh_token) |> post(~p"/api/mobile-release/session")
    assert json_response(reused, 401)["error"]

    wrong_token_type = bearer(pair["access_token"]) |> post(~p"/api/mobile-release/session")
    assert json_response(wrong_token_type, 401)["error"]
  end

  test "members may refresh but cannot export devices or publish", %{member: member} do
    {:ok, tokens} = ApiAuth.issue_token_pair(member)
    refreshed = bearer(tokens.refresh_token) |> post(~p"/api/mobile-release/session")
    access_token = json_response(refreshed, 200)["access_token"]

    denied_devices = bearer(access_token) |> get(~p"/api/mobile-release/devices")
    assert json_response(denied_devices, 403)["error"]

    denied_upload =
      bearer(access_token)
      |> put_req_header("content-type", "multipart/form-data; boundary=broken")
      |> post(~p"/api/mobile-release/ipa", "not multipart")

    assert json_response(denied_upload, 403)["error"]
    assert MobileBuilds.current() == {:error, :not_found}
  end

  test "browser login, missing, invalid and revoked bearer tokens cannot authorize the API",
       context do
    browser = build_conn() |> log_in_user(context.admin)
    assert json_response(get(browser, ~p"/api/mobile-release/devices"), 401)["error"]
    assert json_response(post(browser, ~p"/api/mobile-release/session"), 401)["error"]

    browser_upload =
      browser
      |> put_req_header("content-type", "multipart/form-data; boundary=broken")
      |> post(~p"/api/mobile-release/ipa", "not multipart")

    assert json_response(browser_upload, 401)["error"]

    for token <- [nil, "invalid", context.tokens.refresh_token] do
      denied = bearer(token) |> get(~p"/api/mobile-release/devices")
      assert json_response(denied, 401)["error"]
      assert get_resp_header(denied, "cache-control") == ["no-store"]
    end

    assert {:ok, _time} = ApiAuth.revoke_session(context.admin, context.tokens.session.id)

    revoked_access = bearer(context.tokens.access_token) |> get(~p"/api/mobile-release/devices")
    assert json_response(revoked_access, 401)["error"]

    revoked_refresh =
      bearer(context.tokens.refresh_token) |> post(~p"/api/mobile-release/session")

    assert json_response(revoked_refresh, 401)["error"]
    assert MobileBuilds.current() == {:error, :not_found}
  end

  test "device export contains only this admin's collected identifiers and names", context do
    scope = Scope.for_user(context.admin)
    own = collected(scope, "Own test phone", "00008110-000123456789ABCD")
    {:ok, pending} = Devices.create_invitation(scope, %{label: "Pending test phone"})

    other =
      collected(
        Scope.for_user(context.member),
        "Other owner private label",
        "00008110-000123456789ABCE"
      )

    result = bearer(context.tokens.access_token) |> get(~p"/api/mobile-release/devices")

    assert json_response(result, 200) == %{
             "devices" => [%{"udid" => "00008110-000123456789ABCD", "name" => "Own test phone"}]
           }

    refute result.resp_body =~ other.label
    refute result.resp_body =~ other.share_token
    refute result.resp_body =~ own.share_token
    refute result.resp_body =~ pending.label
    assert get_resp_header(result, "cache-control") == ["no-store"]
  end

  test "access bearer publishes multipart IPA without browser CSRF and replaces it", context do
    first = ipa("first")
    second = ipa("second")
    first_result = upload(context.tokens.access_token, first)
    assert json_response(first_result, 201) == %{"status" => "published"}
    assert get_resp_header(first_result, "cache-control") == ["no-store"]

    replacement = upload(context.tokens.access_token, second)
    assert json_response(replacement, 201) == %{"status" => "published"}

    downloaded = build_conn() |> log_in_user(context.member) |> get(~p"/users/devices/app.ipa")
    assert response(downloaded, 200) == second
    assert File.ls!(context.directory) == ["current.ipa"]
  end

  test "invalid API uploads preserve the current downloadable build", context do
    original = ipa("original")
    assert json_response(upload(context.tokens.access_token, original), 201)
    invalid = upload(context.tokens.access_token, "invalid ZIP")
    assert json_response(invalid, 422)["error"]
    assert get_resp_header(invalid, "cache-control") == ["no-store"]
    downloaded = build_conn() |> log_in_user(context.member) |> get(~p"/users/devices/app.ipa")
    assert response(downloaded, 200) == original
    assert File.ls!(context.directory) == ["current.ipa"]
  end

  defp bearer(token) do
    conn = build_conn() |> put_req_header("accept", "application/json")
    if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
  end

  defp collected(scope, label, udid) do
    {:ok, invitation} = Devices.create_invitation(scope, %{label: label})
    {:ok, token} = Devices.invitation_token(scope, invitation.id)
    {:ok, challenge} = Devices.profile_challenge(token)
    {:ok, :collected} = Devices.complete_invitation(token, challenge, udid)
    %{invitation | share_token: token}
  end

  defp upload(token, binary) do
    body =
      "--release-test-boundary\r\n" <>
        ~s(Content-Disposition: form-data; name="ipa"; filename="Hrafnsyn.ipa"\r\n) <>
        "Content-Type: application/octet-stream\r\n\r\n" <>
        binary <> "\r\n--release-test-boundary--\r\n"

    bearer(token)
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("content-type", "multipart/form-data; boundary=release-test-boundary")
    |> post(~p"/api/mobile-release/ipa", body)
  end

  defp ipa(contents) do
    {:ok, {_name, binary}} =
      :zip.create(~c"fixture.ipa", [{~c"Payload/Test.app/Info.plist", contents}], [:memory])

    binary
  end
end
