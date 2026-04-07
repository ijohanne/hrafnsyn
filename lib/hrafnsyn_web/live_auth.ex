defmodule HrafnsynWeb.LiveAuth do
  @moduledoc false

  use HrafnsynWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Hrafnsyn.Accounts
  alias Hrafnsyn.Accounts.Scope
  alias HrafnsynWeb.UserAuth

  def on_mount(:mount_current_scope, _params, session, socket) do
    scope =
      case session["user_token"] do
        nil ->
          nil

        token ->
          case Accounts.get_user_by_session_token(token) do
            {user, _inserted_at} -> Scope.for_user(user)
            nil -> nil
          end
      end

    {:cont, assign(socket, :current_scope, scope)}
  end

  def on_mount(:ensure_authenticated_user, _params, _session, socket) do
    if socket.assigns.current_scope do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "You must log in to access this page.")
       |> redirect(to: ~p"/users/log-in")}
    end
  end

  def on_mount(:ensure_admin, _params, _session, socket) do
    if Scope.admin?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "Admin access required.")
       |> redirect(to: ~p"/")}
    end
  end

  def on_mount(:ensure_authenticated_user_unless_public, _params, _session, socket) do
    if UserAuth.public_readonly?() || socket.assigns.current_scope do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "You must log in to access this page.")
       |> redirect(to: ~p"/users/log-in")}
    end
  end
end
