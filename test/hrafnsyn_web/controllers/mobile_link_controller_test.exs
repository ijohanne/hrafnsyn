defmodule HrafnsynWeb.MobileLinkControllerTest do
  use HrafnsynWeb.ConnCase, async: false

  setup do
    original_ids = Application.get_env(:hrafnsyn, :ios_app_ids, [])
    original_public = Application.get_env(:hrafnsyn, :public_readonly?, true)

    on_exit(fn ->
      Application.put_env(:hrafnsyn, :ios_app_ids, original_ids)
      Application.put_env(:hrafnsyn, :public_readonly?, original_public)
    end)

    :ok
  end

  test "association is public JSON even when tracks require authentication", %{conn: conn} do
    Application.put_env(:hrafnsyn, :public_readonly?, false)
    Application.put_env(:hrafnsyn, :ios_app_ids, ["ABCDE12345.io.example.tracking"])

    conn = get(conn, "/.well-known/apple-app-site-association")
    assert %{"applinks" => %{"details" => [detail]}} = json_response(conn, 200)
    assert detail["appIDs"] == ["ABCDE12345.io.example.tracking"]

    assert %{"/" => "/", "?" => %{"vehicle" => "plane", "identity" => "?*"}} in detail[
             "components"
           ]

    assert %{"/" => "/", "?" => %{"vehicle" => "vessel", "identity" => "?*"}} in detail[
             "components"
           ]

    assert %{"#" => "no_universal_links", "exclude" => true} in detail["components"]
    refute Enum.any?(detail["components"], &(&1["/"] == "*"))
    assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "unconfigured builds claim no domains", %{conn: conn} do
    Application.put_env(:hrafnsyn, :ios_app_ids, [])

    assert get(conn, "/apple-app-site-association") |> json_response(200) == %{
             "applinks" => %{"details" => []}
           }
  end

  test "private shared link offers app handoff before browser login", %{conn: conn} do
    Application.put_env(:hrafnsyn, :public_readonly?, false)
    conn = get(conn, "/?vehicle=vessel&identity=242080116&range=24")
    assert redirected_to(conn) == "/users/log-in"
    conn = conn |> recycle() |> get("/users/log-in")
    html = html_response(conn, 200)
    assert html =~ "Open shared track in app"
    assert html =~ "hrafnsyn://open?url="
    assert html =~ "identity%3D242080116"
    assert html =~ "range%3D24"
  end

  test "ordinary login does not offer an unrelated app target", %{conn: conn} do
    html = conn |> get("/users/log-in") |> html_response(200)
    refute html =~ "open-shared-track-in-app"
  end
end
