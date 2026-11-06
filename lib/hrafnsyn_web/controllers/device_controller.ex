defmodule HrafnsynWeb.DeviceController do
  use HrafnsynWeb, :controller

  alias Hrafnsyn.Devices
  alias Hrafnsyn.Devices.{Invitation, Profile}
  alias HrafnsynWeb.Endpoint

  require Logger

  plug :private_response

  def index(conn, _params), do: render_index(conn, Devices.change_invitation(%Invitation{}, %{}))

  def create(conn, %{"invitation" => params}) when is_map(params) do
    case Devices.create_invitation(conn.assigns.current_scope, params) do
      {:ok, _invitation} ->
        conn
        |> put_flash(
          :info,
          "Invitation created. Share its link with the owner of one iPhone or iPad."
        )
        |> redirect(to: ~p"/users/devices")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> render_index(changeset)

      {:error, :limit_reached} ->
        conn
        |> put_flash(
          :error,
          "You have 25 saved invitations. Delete an old invitation before creating another."
        )
        |> redirect(to: ~p"/users/devices")

      {:error, _reason} ->
        conn
        |> put_flash(
          :error,
          "Could not create an invitation. Delete an old invitation and try again."
        )
        |> redirect(to: ~p"/users/devices")
    end
  end

  def create(conn, _params), do: conn |> put_status(:bad_request) |> index(%{})

  def delete(conn, %{"id" => id}) do
    case Devices.delete_invitation(conn.assigns.current_scope, id) do
      {:ok, _invitation} ->
        conn
        |> put_flash(:info, "Invitation and any collected identifier deleted.")
        |> redirect(to: ~p"/users/devices")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "That invitation is no longer available.")
        |> redirect(to: ~p"/users/devices")
    end
  end

  def invite(conn, %{"token" => token}) do
    case Devices.get_public_invitation(token) do
      {:ok, %{status: status} = invitation} when status in [:pending, :collected] ->
        render_invite(conn, invitation, token, status)

      _ ->
        render_unavailable(conn)
    end
  end

  def profile(conn, %{"token" => token}) do
    with {:ok, %{status: :pending, id: id}} <- Devices.get_public_invitation(token),
         {:ok, challenge} <- Devices.profile_challenge(token),
         {:ok, body} <-
           Profile.generate(absolute_url(~p"/devices/invite/#{token}/callback"), challenge, id) do
      send_download(conn, {:binary, body},
        filename: "Hrafnsyn-Device.mobileconfig",
        content_type: "application/x-apple-aspen-config"
      )
    else
      {:error, :invalid_profile} ->
        conn
        |> put_status(:service_unavailable)
        |> text("Device collection requires a configured HTTPS server address.")

      _ ->
        render_unavailable(conn)
    end
  end

  def callback(conn, %{"token" => token}) do
    with {:ok, challenge} <- Devices.profile_challenge(token),
         {:ok, udid} <-
           parse_device_response(conn.private[:device_callback_body] || "", challenge),
         {:ok, :collected} <- Devices.complete_invitation(token, challenge, udid) do
      # iOS profile services hand this redirect back to Safari; no identifier enters the URL.
      conn
      |> put_resp_header("location", absolute_url(~p"/devices/invite/#{token}"))
      |> send_resp(301, "")
    else
      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          400,
          "Could not accept this device response. Return to the invitation in Safari and check its status, or ask for a new link."
        )
    end
  end

  defp parse_device_response(body, challenge) do
    case Profile.parse_callback_detailed(body, challenge) do
      {:ok, udid} ->
        {:ok, udid}

      {:error, reason} ->
        # Only fixed categories are logged, never the invitation or device response.
        category =
          if reason in [:invalid_cms, :invalid_plist, :challenge_mismatch, :invalid_udid],
            do: reason,
            else: :invalid_callback

        Logger.warning("Device profile callback rejected: #{category}")
        {:error, :invalid_callback}
    end
  end

  defp render_index(conn, changeset) do
    scope = conn.assigns.current_scope
    invitations = Devices.list_invitations(scope)

    share_urls =
      Map.new(invitations, fn invitation ->
        {invitation.id, absolute_url(~p"/devices/invite/#{invitation.share_token}")}
      end)

    render(conn, :index,
      page_title: "iOS devices",
      mobile_build: Hrafnsyn.MobileBuilds.current(),
      invitations: invitations,
      form: Phoenix.Component.to_form(changeset, as: :invitation),
      share_urls: share_urls
    )
  end

  defp render_invite(conn, invitation, token, status) do
    render(conn, :invite,
      page_title: "Share your device ID",
      invitation: invitation,
      owner_name: invitation.owner_name,
      profile_url: ~p"/devices/invite/#{token}/profile",
      status: status,
      error: nil
    )
  end

  defp render_unavailable(conn) do
    conn
    |> put_status(:not_found)
    |> render(:invite,
      page_title: "Invitation unavailable",
      invitation: nil,
      owner_name: nil,
      profile_url: nil,
      status: :unavailable,
      error: nil
    )
  end

  defp absolute_url(path), do: String.trim_trailing(Endpoint.url(), "/") <> path

  defp private_response(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-robots-tag", "noindex, nofollow, noarchive")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
