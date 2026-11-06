defmodule HrafnsynWeb.MobileReleaseController do
  use HrafnsynWeb, :controller

  alias Hrafnsyn.Accounts.ApiAuth
  alias Hrafnsyn.{Devices, MobileBuilds}
  alias HrafnsynWeb.Plugs.MobileReleaseAuth

  plug :private_response

  def refresh(conn, _params) do
    with {:ok, token} <- MobileReleaseAuth.bearer_token(conn),
         {:ok, pair} <- ApiAuth.refresh(token) do
      json(conn, %{access_token: pair.access_token, refresh_token: pair.refresh_token})
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "A valid API refresh token is required."})
    end
  end

  def devices(conn, _params) do
    devices =
      conn.assigns.current_scope
      |> Devices.list_invitations()
      |> Enum.filter(&(&1.udid && Devices.invitation_status(&1) == :collected))
      |> Enum.map(&%{udid: &1.udid, name: &1.label})
      |> Enum.uniq_by(& &1.udid)

    json(conn, %{devices: devices})
  end

  def publish(conn, params) do
    case MobileBuilds.publish(conn.assigns.current_scope, params["ipa"]) do
      :ok ->
        conn |> put_status(:created) |> json(%{status: "published"})

      {:error, :too_large} ->
        conn |> put_status(413) |> json(%{error: "IPA exceeds 250 MiB."})

      {:error, :invalid_ipa} ->
        conn |> put_status(422) |> json(%{error: "Choose a valid IPA."})

      {:error, :forbidden} ->
        conn |> put_status(403) |> json(%{error: "Administrator access is required."})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{error: "The IPA could not be saved. The current file has not changed."})
    end
  end

  defp private_response(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-robots-tag", "noindex, nofollow, noarchive")
  end
end
