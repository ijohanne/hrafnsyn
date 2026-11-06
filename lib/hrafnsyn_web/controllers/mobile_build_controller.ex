defmodule HrafnsynWeb.MobileBuildController do
  use HrafnsynWeb, :controller

  alias Hrafnsyn.MobileBuilds

  plug :private_response

  def create(conn, params) do
    case MobileBuilds.publish(conn.assigns.current_scope, params["ipa"]) do
      :ok ->
        conn
        |> put_flash(
          :info,
          "IPA published. Signed-in users can download it now; the previous file was replaced."
        )
        |> redirect(to: ~p"/users/devices")

      {:error, reason} ->
        conn
        |> put_flash(:error, upload_error(reason))
        |> redirect(to: ~p"/users/devices")
    end
  end

  def download(conn, _params) do
    result =
      MobileBuilds.with_download(conn.assigns.current_scope, fn path ->
        send_current_ipa(conn, path)
      end)

    case result do
      {:ok, conn} ->
        conn

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text("No IPA has been uploaded yet.")

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> text("Sign in to download the app.")

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> text("The IPA is temporarily unavailable. Please try again later.")
    end
  end

  # The context supplies a UUID-named hard link under the configured private
  # directory. No request parameter or uploaded filename is part of this path.
  # sobelow_skip ["Traversal.SendDownload"]
  defp send_current_ipa(conn, path) do
    send_download(conn, {:file, path},
      filename: "Hrafnsyn.ipa",
      content_type: "application/octet-stream"
    )
  end

  defp upload_error(:invalid_ipa),
    do: "Choose an IPA containing an iOS app. The current download has not changed."

  defp upload_error(:too_large),
    do: "Choose an IPA of 250 MiB or less. The current download has not changed."

  defp upload_error(:forbidden), do: "Only an administrator can upload an IPA."

  defp upload_error(_reason),
    do: "The IPA could not be saved. The current download has not changed. Please try again."

  defp private_response(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-robots-tag", "noindex, nofollow, noarchive")
  end
end
