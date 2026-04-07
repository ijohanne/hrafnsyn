defmodule HrafnsynWeb.LiveAuth do
  @moduledoc false

  use HrafnsynWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Hrafnsyn.Accounts
  alias Hrafnsyn.Accounts.Scope

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
end
