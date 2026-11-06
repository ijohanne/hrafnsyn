defmodule HrafnsynWeb.MobileInstallControllerTest do
  use HrafnsynWeb.ConnCase, async: false

  import Hrafnsyn.AccountsFixtures
  import ExUnit.CaptureLog

  alias Hrafnsyn.{Accounts, MobileBuilds, MobileInstallations, Repo}
  alias Hrafnsyn.Accounts.Scope
  alias HrafnsynWeb.Endpoint

  setup do
    root = Path.join(System.tmp_dir!(), "hrafnsyn-ota-#{Ecto.UUID.generate()}")
    directory = Path.join(root, "published")
    old_directory = Application.fetch_env(:hrafnsyn, :mobile_build_directory)
    endpoint_config = Application.fetch_env!(:hrafnsyn, Endpoint)
    Application.put_env(:hrafnsyn, :mobile_build_directory, directory)
    File.mkdir_p!(root)
    configure_url(endpoint_config, "https")

    on_exit(fn ->
      File.rm_rf!(root)
      Endpoint.config_change([{Endpoint, endpoint_config}], [])

      case old_directory do
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

    %{
      root: root,
      directory: directory,
      admin: admin,
      member: user_fixture(),
      config: endpoint_config
    }
  end

  test "installation starts behind login and uses the configured HTTPS origin", context do
    anonymous = get(build_conn(), ~p"/users/devices/install")
    assert redirected_to(anonymous) == ~p"/users/log-in"
    publish(context)

    page =
      build_conn()
      |> Map.put(:host, "untrusted.example")
      |> log_in_user(context.member)
      |> get(~p"/users/devices/install")

    html = html_response(page, 200)
    assert html =~ "itms-services://?"
    assert html =~ "tracks.example.com"
    refute html =~ "untrusted.example"
    assert get_resp_header(page, "cache-control") == ["no-store"]
    assert get_resp_header(page, "referrer-policy") == ["no-referrer"]
  end

  test "cookie-free manifest and IPA requests deliver the actual build metadata and bytes",
       context do
    bytes = publish(context)
    manifest_path = install_path(context.member)
    response = get(build_conn(), manifest_path)
    xml = response(response, 200)
    assert get_resp_header(response, "content-type") == ["text/xml; charset=utf-8"]
    assert xml =~ "<string>io.example.fixture</string>"
    assert xml =~ "<string>42</string>"
    assert xml =~ "<string>Flight &amp; Harbour</string>"
    ipa_path = ipa_path(xml)
    ipa = get(build_conn(), ipa_path)
    assert response(ipa, 200) == bytes
    assert get_resp_header(ipa, "content-type") == ["application/octet-stream"]
    assert get_resp_header(ipa, "cache-control") == ["no-store"]
    assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
    assert File.ls!(context.directory) == ["current.ipa"]

    head = head(build_conn(), ipa_path)
    assert response(head, 200) == ""
  end

  test "missing, tampered, and wrong-purpose grants never expose the IPA", context do
    publish(context)
    path = install_path(context.member)
    token = path |> String.split("/") |> Enum.at(2)
    xml = build_conn() |> get(path) |> response(200)
    ipa_token = xml |> ipa_path() |> String.split("/") |> Enum.at(2)

    for path <- [
          "/mobile-install/invalid/manifest.plist",
          "/mobile-install/#{token}modified/manifest.plist",
          "/mobile-install/#{token}/app.ipa",
          "/mobile-install/#{ipa_token}/manifest.plist"
        ] do
      result = get(build_conn(), path)
      assert response(result, 404) =~ "expired or unavailable"
      assert get_resp_header(result, "cache-control") == ["no-store"]
    end
  end

  test "endpoint and router logging never expose installation grants", context do
    publish(context)
    manifest_path = install_path(context.member)
    ipa_path = build_conn() |> get(manifest_path) |> response(200) |> ipa_path()
    paths = [manifest_path, ipa_path, "/mobile-install/private-invalid-grant/manifest.plist"]
    original_level = Logger.level()
    Logger.configure(level: :debug)

    try do
      log =
        capture_log([level: :debug], fn ->
          for path <- paths, do: get(build_conn(), path)
          assert html_response(get(build_conn(), ~p"/grpc"), 200) =~ "gRPC"
        end)

      # Prove request logging is active; otherwise a quiet test logger could
      # conceal a bearer URL leaking at production's info level.
      assert log =~ "GET /grpc"

      for path <- paths do
        token = path |> String.split("/") |> Enum.at(2)
        refute log =~ token
      end
    after
      Logger.configure(level: original_level)
    end
  end

  test "absolute expiry is enforced for both manifest and IPA grants", context do
    publish(context)
    token = install_path(context.member) |> String.split("/") |> Enum.at(2)

    {:ok, grant} =
      Phoenix.Token.verify(Endpoint, "mobile-install-manifest-v1", token, max_age: 900)

    expired = %{grant | expires_at: System.system_time(:second) - 1}

    for {purpose, filename} <- [{"manifest", "manifest.plist"}, {"ipa", "app.ipa"}] do
      expired_token = Phoenix.Token.sign(Endpoint, "mobile-install-#{purpose}-v1", expired)
      result = get(build_conn(), "/mobile-install/#{expired_token}/#{filename}")
      assert response(result, 404) =~ "expired or unavailable"
    end
  end

  test "reading a manifest does not extend the original installation deadline", context do
    publish(context)
    path = install_path(context.member)
    token = path |> String.split("/") |> Enum.at(2)

    {:ok, original} =
      Phoenix.Token.verify(Endpoint, "mobile-install-manifest-v1", token, max_age: 900)

    shortened = %{original | expires_at: System.system_time(:second) + 60}
    token = Phoenix.Token.sign(Endpoint, "mobile-install-manifest-v1", shortened)
    xml = build_conn() |> get("/mobile-install/#{token}/manifest.plist") |> response(200)
    ipa_token = xml |> ipa_path() |> String.split("/") |> Enum.at(2)

    {:ok, download_grant} =
      Phoenix.Token.verify(Endpoint, "mobile-install-ipa-v1", ipa_token, max_age: 900)

    assert download_grant.expires_at == shortened.expires_at
  end

  test "publishing a replacement invalidates both old manifest and IPA links", context do
    publish(context)
    manifest = install_path(context.member)
    ipa = build_conn() |> get(manifest) |> response(200) |> ipa_path()
    publish(context, "43")
    assert response(get(build_conn(), manifest), 404) =~ "expired or unavailable"
    assert response(get(build_conn(), ipa), 404) =~ "expired or unavailable"
    assert response(get(build_conn(), install_path(context.member)), 200) =~ "<string>43</string>"
    assert File.ls!(context.directory) == ["current.ipa"]
  end

  test "removing the account revokes both grants", context do
    publish(context)
    manifest = install_path(context.member)
    ipa = build_conn() |> get(manifest) |> response(200) |> ipa_path()
    Repo.delete!(context.member)
    assert response(get(build_conn(), manifest), 404) =~ "expired or unavailable"
    assert response(get(build_conn(), ipa), 404) =~ "expired or unavailable"
    assert {:error, :forbidden} = MobileInstallations.prepare(Scope.for_user(context.member))
  end

  test "HTTP configuration cannot issue installation grants", context do
    publish(context)
    configure_url(context.config, "http")
    assert {:error, :https_required} = MobileInstallations.prepare(Scope.for_user(context.member))
    page = build_conn() |> log_in_user(context.member) |> get(~p"/users/devices/install")
    assert redirected_to(page) == ~p"/users/devices"
    assert Phoenix.Flash.get(page.assigns.flash, :error) =~ "HTTPS"
  end

  test "missing and malformed build metadata cannot produce install links", context do
    assert {:error, :not_found} = MobileInstallations.prepare(Scope.for_user(context.member))
    publish(context, "42", "not a property list")
    assert {:error, :invalid_ipa} = MobileInstallations.prepare(Scope.for_user(context.member))
    assert File.ls!(context.directory) == ["current.ipa"]
    assert {:error, :forbidden} = MobileInstallations.prepare(nil)
  end

  defp configure_url(config, scheme) do
    config = Keyword.put(config, :url, scheme: scheme, host: "tracks.example.com", port: 443)
    Endpoint.config_change([{Endpoint, config}], [])
  end

  defp install_path(user) do
    {:ok, %{install_url: url}} = MobileInstallations.prepare(Scope.for_user(user))

    manifest_url =
      url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("url")

    assert URI.parse(manifest_url).host == "tracks.example.com"
    URI.parse(manifest_url).path
  end

  defp ipa_path(xml) do
    [url] = Regex.run(~r{<key>url</key><string>([^<]+)</string>}, xml, capture: :all_but_first)
    assert URI.parse(url).host == "tracks.example.com"
    URI.parse(url).path
  end

  defp publish(context, version \\ "42", contents \\ nil) do
    contents =
      contents ||
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>io.example.fixture</string>
        <key>CFBundleVersion</key><string>#{version}</string>
        <key>CFBundleDisplayName</key><string>Flight &amp; Harbour</string>
        </dict></plist>
        """

    {:ok, {_name, bytes}} =
      :zip.create(~c"fixture.ipa", [{~c"Payload/Test.app/Info.plist", contents}], [:memory])

    path = Path.join(context.root, "fixture.ipa")
    File.write!(path, bytes)

    upload = %Plug.Upload{
      path: path,
      filename: "Fixture.ipa",
      content_type: "application/octet-stream"
    }

    assert :ok = MobileBuilds.publish(Scope.for_user(context.admin), upload)
    bytes
  end
end
