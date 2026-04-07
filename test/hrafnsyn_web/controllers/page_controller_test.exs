defmodule HrafnsynWeb.PageControllerTest do
  use HrafnsynWeb.ConnCase

  alias HrafnsynWeb.Endpoint

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Air and sea traffic on one living map."
    assert response =~ "Live Contacts"
    assert response =~ "gRPC API"
  end

  test "GET /grpc renders the API docs and service surface", %{conn: conn} do
    conn = get(conn, ~p"/grpc")
    response = html_response(conn, 200)

    assert response =~ "Hrafnsyn gRPC API"
    assert response =~ "Download `tracking.proto`"
    assert response =~ "TrackingService"
    assert response =~ "StreamTrackUpdates"
    assert response =~ "StreamObservationsRequest"
    assert response =~ "VehicleType"
  end

  test "GET /grpc renders deployment-aware quick start commands", %{conn: conn} do
    conn = %{conn | host: "devbox.local", scheme: :http, port: 4000}
    conn = get(conn, ~p"/grpc")
    response = html_response(conn, 200)

    assert response =~ "http://devbox.local:4000/grpc/tracking.proto"
    assert response =~ "grpcurl -plaintext -import-path . -proto tracking.proto"
    assert response =~ "devbox.local:4000 hrafnsyn.v1.TrackingService/GetSystemInfo"
  end

  test "GET /grpc prefers the configured external endpoint URL", %{conn: conn} do
    original_config = Application.fetch_env!(:hrafnsyn, Endpoint)

    on_exit(fn ->
      Application.put_env(:hrafnsyn, Endpoint, original_config)
    end)

    Application.put_env(:hrafnsyn, Endpoint,
      Keyword.put(original_config, :url,
        scheme: "https",
        host: "tracks.example.com",
        port: 443
      )
    )

    conn = %{conn | host: "127.0.0.1", scheme: :http, port: 4000}
    conn = get(conn, ~p"/grpc")
    response = html_response(conn, 200)

    assert response =~ "https://tracks.example.com/grpc/tracking.proto"
    assert response =~ "grpcurl -import-path . -proto tracking.proto"
    refute response =~ "grpcurl -plaintext -import-path . -proto tracking.proto"
    assert response =~ "tracks.example.com hrafnsyn.v1.TrackingService/GetSystemInfo"
  end

  test "GET /grpc/tracking.proto downloads the published proto", %{conn: conn} do
    conn = get(conn, ~p"/grpc/tracking.proto")

    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(filename="tracking.proto")
    assert response(conn, 200) =~ ~s(syntax = "proto3";)
    assert response(conn, 200) =~ "service TrackingService"
  end
end
