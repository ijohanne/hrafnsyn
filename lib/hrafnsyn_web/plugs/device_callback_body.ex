defmodule HrafnsynWeb.Plugs.DeviceCallbackBody do
  @moduledoc "Reads Apple's bounded CMS callback before the general request parsers."
  import Plug.Conn

  alias Hrafnsyn.Devices.Profile

  def init(opts), do: opts

  def call(%{method: "POST", path_info: ["devices", "invite", _token, "callback"]} = conn, _opts) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("x-content-type-options", "nosniff")

    if supported_content_type?(conn) do
      read_callback(conn)
    else
      conn |> send_resp(415, "A signed device response is required.") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp supported_content_type?(conn) do
    case get_req_header(conn, "content-type") do
      [type] ->
        media_type =
          type |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()

        media_type in [
          "application/pkcs7-signature",
          "application/x-pkcs7-signature",
          "application/pkcs7-mime"
        ]

      _ ->
        false
    end
  end

  defp read_callback(conn) do
    limit = Profile.max_body_bytes()

    case read_body(conn, length: limit, read_length: limit, read_timeout: 5_000) do
      {:ok, body, conn} when byte_size(body) <= limit ->
        put_private(conn, :device_callback_body, body)

      {:more, _body, conn} ->
        conn |> send_resp(413, "The device response is too large.") |> halt()

      {:ok, _body, conn} ->
        conn |> send_resp(413, "The device response is too large.") |> halt()

      {:error, _reason} ->
        conn |> send_resp(400, "The device response could not be read.") |> halt()
    end
  end
end
