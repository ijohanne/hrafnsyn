defmodule HrafnsynWeb.MobileInstallController do
  use HrafnsynWeb, :controller

  alias Hrafnsyn.MobileInstallations

  plug :private_response

  def index(conn, _params) do
    case MobileInstallations.prepare(conn.assigns.current_scope) do
      {:ok, assigns} ->
        render(conn, :index, Map.to_list(assigns))

      {:error, reason} ->
        conn
        |> put_flash(:error, installation_error(reason))
        |> redirect(to: ~p"/users/devices")
    end
  end

  def manifest(conn, %{"token" => token}) do
    case MobileInstallations.manifest(token) do
      {:ok, xml} ->
        conn |> put_resp_content_type("text/xml") |> send_resp(:ok, xml)

      {:error, reason} ->
        unavailable(conn, reason)
    end
  end

  def ipa(conn, %{"token" => token}) do
    case MobileInstallations.with_ipa(token, &send_ipa(conn, &1)) do
      {:ok, conn} -> conn
      {:error, reason} -> unavailable(conn, reason)
    end
  end

  # The context authorizes the grant and supplies a generated hard link beneath
  # private storage. No URL, filename or token supplies any part of this path.
  # sobelow_skip ["Traversal.SendDownload"]
  defp send_ipa(conn, path) do
    send_download(conn, {:file, path},
      filename: "Hrafnsyn.ipa",
      content_type: "application/octet-stream"
    )
  end

  defp unavailable(conn, reason) when reason in [:forbidden, :not_found],
    do:
      conn
      |> put_status(:not_found)
      |> text("Installation link expired or unavailable. Sign in to start again.")

  defp unavailable(conn, _reason),
    do:
      conn
      |> put_status(:service_unavailable)
      |> text("The app is temporarily unavailable. Please try again later.")

  defp installation_error(:https_required),
    do: "Web installation requires the server to have a public HTTPS address."

  defp installation_error(reason) when reason in [:invalid_ipa, :metadata_unavailable],
    do:
      "This IPA is not ready for web installation. An administrator needs to upload a valid iOS build."

  defp installation_error(_reason),
    do: "No installable build is available. Please try again later."

  defp private_response(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-robots-tag", "noindex, nofollow, noarchive")
  end
end
