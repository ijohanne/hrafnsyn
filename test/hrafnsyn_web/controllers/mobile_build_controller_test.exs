defmodule HrafnsynWeb.MobileBuildControllerTest do
  use HrafnsynWeb.ConnCase, async: false

  import Hrafnsyn.AccountsFixtures

  alias Hrafnsyn.{Accounts, MobileBuilds}

  setup do
    root = Path.join(System.tmp_dir!(), "hrafnsyn-ipa-web-#{Ecto.UUID.generate()}")
    directory = Path.join(root, "published")
    previous = Application.fetch_env(:hrafnsyn, :mobile_build_directory)
    Application.put_env(:hrafnsyn, :mobile_build_directory, directory)
    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf!(root)

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

    %{directory: directory, admin: admin, member: user_fixture()}
  end

  test "downloads require login and uploads authorize before parsing their body", %{
    conn: conn,
    member: member
  } do
    assert redirected_to(get(conn, ~p"/users/devices/app.ipa")) == ~p"/users/log-in"

    anonymous =
      conn
      |> put_req_header("content-type", "multipart/form-data; boundary=broken")
      |> post(~p"/admin/mobile-build", "not multipart")

    assert redirected_to(anonymous) == ~p"/users/log-in"

    forbidden =
      build_conn()
      |> log_in_user(member)
      |> put_req_header("content-type", "multipart/form-data; boundary=broken")
      |> post(~p"/admin/mobile-build", "not multipart")

    assert response(forbidden, 403) =~ "Administrator access"
    assert MobileBuilds.current() == {:error, :not_found}
  end

  test "members see availability but only admins see the upload form", context do
    member_page = build_conn() |> log_in_user(context.member) |> get(~p"/users/devices")
    member_html = html_response(member_page, 200)
    refute member_html =~ ~s(action="/admin/mobile-build")
    refute member_html =~ ~s(href="/users/devices/app.ipa")

    admin_page = build_conn() |> log_in_user(context.admin) |> get(~p"/users/devices")
    admin_html = html_response(admin_page, 200)
    assert admin_html =~ ~s(action="/admin/mobile-build")
    assert admin_html =~ ~s(enctype="multipart/form-data")
    assert admin_html =~ ~s(name="ipa")

    result = publish(context.admin, ipa("first"))
    assert redirected_to(result) == ~p"/users/devices"

    available_page = build_conn() |> log_in_user(context.member) |> get(~p"/users/devices")
    available_html = html_response(available_page, 200)
    assert available_html =~ ~s(href="/users/devices/app.ipa")
    assert available_html =~ "Download IPA"
    refute available_html =~ ~s(action="/admin/mobile-build")
  end

  test "multipart publication replaces the only download and serves private bytes", context do
    first = ipa("first")
    second = ipa("second")
    assert redirected_to(publish(context.admin, first)) == ~p"/users/devices"
    assert response(download(context.member), 200) == first
    assert redirected_to(publish(context.admin, second)) == ~p"/users/devices"

    result = download(context.member)
    assert response(result, 200) == second
    assert get_resp_header(result, "cache-control") == ["no-store"]
    assert get_resp_header(result, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(result, "content-type") == ["application/octet-stream"]
    assert [disposition] = get_resp_header(result, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "Hrafnsyn.ipa"
    assert File.ls!(context.directory) == ["current.ipa"]
  end

  test "invalid files and unsupported request types preserve the current build", context do
    original = ipa("original")
    publish(context.admin, original)
    invalid = publish(context.admin, "invalid ZIP")
    assert redirected_to(invalid) == ~p"/users/devices"
    assert Phoenix.Flash.get(invalid.assigns.flash, :error) =~ "current download has not changed"
    assert response(download(context.member), 200) == original

    unsupported =
      build_conn()
      |> log_in_user(context.admin)
      |> put_req_header("content-type", "application/octet-stream")
      |> post(~p"/admin/mobile-build", original)

    assert response(unsupported, 415) =~ "Choose an IPA"
    assert response(download(context.member), 200) == original
    assert File.ls!(context.directory) == ["current.ipa"]
  end

  test "a missing build returns a private unavailable response", %{member: member} do
    result = download(member)
    assert response(result, 404) =~ "No IPA has been uploaded"
    assert get_resp_header(result, "cache-control") == ["no-store"]
  end

  test "an authorized IPA can exceed the ordinary request parser limit", context do
    {:ok, {_name, binary}} =
      :zip.create(
        ~c"large-fixture.ipa",
        [{~c"Payload/Test.app/Info.plist", :binary.copy("x", 8_100_000)}],
        [:memory, {:compress, []}]
      )

    assert byte_size(binary) > 8_000_000
    assert redirected_to(publish(context.admin, binary)) == ~p"/users/devices"
    assert {:ok, %{size: size}} = MobileBuilds.current()
    assert size == byte_size(binary)
  end

  test "multipart uploads enforce CSRF and accept the token from the rendered form", context do
    body = multipart(ipa("csrf"))

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      build_conn()
      |> log_in_user(context.admin)
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "multipart/form-data; boundary=ipa-test-boundary")
      |> post(~p"/admin/mobile-build", body)
    end

    assert MobileBuilds.current() == {:error, :not_found}

    page = build_conn() |> log_in_user(context.admin) |> get(~p"/users/devices")

    [token | _] =
      page
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("form[action='/admin/mobile-build'] input[name='_csrf_token']")
      |> LazyHTML.attribute("value")

    result =
      page
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "multipart/form-data; boundary=ipa-test-boundary")
      |> post(~p"/admin/mobile-build", multipart(ipa("csrf"), token))

    assert redirected_to(result) == ~p"/users/devices"
    assert {:ok, _metadata} = MobileBuilds.current()
  end

  defp publish(admin, binary) do
    build_conn()
    |> log_in_user(admin)
    |> put_req_header("content-type", "multipart/form-data; boundary=ipa-test-boundary")
    |> post(~p"/admin/mobile-build", multipart(binary))
  end

  defp download(member) do
    build_conn() |> log_in_user(member) |> get(~p"/users/devices/app.ipa")
  end

  defp multipart(binary, csrf_token \\ nil) do
    token_part =
      if csrf_token do
        "--ipa-test-boundary\r\n" <>
          "Content-Disposition: form-data; name=\"_csrf_token\"\r\n\r\n" <>
          csrf_token <> "\r\n"
      else
        ""
      end

    token_part <>
      "--ipa-test-boundary\r\n" <>
      ~s(Content-Disposition: form-data; name="ipa"; filename="Hrafnsyn.ipa"\r\n) <>
      "Content-Type: application/octet-stream\r\n\r\n" <>
      binary <> "\r\n--ipa-test-boundary--\r\n"
  end

  defp ipa(contents) do
    {:ok, {_name, binary}} =
      :zip.create(~c"fixture.ipa", [{~c"Payload/Test.app/Info.plist", contents}], [:memory])

    binary
  end
end
