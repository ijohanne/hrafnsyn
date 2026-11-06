defmodule HrafnsynWeb.Plugs.MobileReleaseAuth do
  @moduledoc "Authorizes release automation using revocable API credentials, never browser cookies."
  import Plug.Conn
  alias Hrafnsyn.Accounts.{ApiAuth, Scope}

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with {:ok, token} <- bearer_token(conn),
         {:ok, auth} <- ApiAuth.authenticate_access_token(token) do
      if Scope.admin?(auth.scope) do
        assign(conn, :current_scope, auth.scope)
      else
        reject(conn, 403, "Administrator access is required.")
      end
    else
      _ -> reject(conn, 401, "A valid API access token is required.")
    end
  end

  def bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 and byte_size(token) <= 8192 -> {:ok, token}
      _ -> {:error, :unauthorized}
    end
  end

  defp reject(conn, status, message) do
    conn |> put_status(status) |> Phoenix.Controller.json(%{error: message}) |> halt()
  end
end
