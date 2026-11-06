defmodule HrafnsynWeb.Plugs.MobileUpload do
  @moduledoc "Parses bounded IPA uploads after administrator authorization."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "content-type") do
      ["multipart/form-data" <> _] -> parse(conn)
      _ -> reject(conn, 415, "Choose an IPA file on the device page and try again.")
    end
  end

  defp parse(conn) do
    options =
      Plug.Parsers.init(
        parsers: [:multipart],
        length: Hrafnsyn.MobileBuilds.max_bytes() + 1024 * 1024,
        read_timeout: 60_000
      )

    Plug.Parsers.call(conn, options)
  rescue
    Plug.Parsers.RequestTooLargeError ->
      reject(
        conn,
        413,
        "This upload is too large. Return to the device page and choose an IPA of 250 MiB or less."
      )

    Plug.Parsers.ParseError ->
      reject(
        conn,
        400,
        "The upload could not be read. Return to the device page and choose the file again."
      )
  end

  defp reject(conn, status, message) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
    |> halt()
  end
end
