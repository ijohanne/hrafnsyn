defmodule Hrafnsyn.GRPC.AuthInterceptor do
  @moduledoc false

  @behaviour GRPC.Server.Interceptor

  alias Hrafnsyn.Accounts.ApiAuth
  alias Hrafnsyn.Accounts.Scope

  @impl true
  def init(opts), do: opts

  @impl true
  def call(req, stream, next, _opts) do
    token = bearer_token(stream)

    case authorize(stream, token) do
      {:ok, auth} ->
        next.(req, %{stream | local: %{auth: auth}})

      {:error, :forbidden} ->
        {:error, GRPC.RPCError.exception(:permission_denied, "Admin privileges are required")}

      {:error, :invalid_credentials} ->
        {:error, GRPC.RPCError.exception(:unauthenticated, "Invalid credentials")}

      {:error, :revoked} ->
        {:error, GRPC.RPCError.exception(:unauthenticated, "Token has been revoked")}

      {:error, _reason} ->
        {:error, GRPC.RPCError.exception(:unauthenticated, "Authentication required")}
    end
  end

  defp authorize(stream, token) do
    case policy(stream) do
      :none ->
        {:ok, nil}

      :optional ->
        optional_auth(token)

      :authenticated ->
        required_auth(token)

      :admin ->
        with {:ok, auth} <- required_auth(token),
             true <- Scope.admin?(auth.scope) do
          {:ok, auth}
        else
          false -> {:error, :forbidden}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp optional_auth(nil), do: {:ok, nil}

  defp optional_auth(token) do
    case ApiAuth.authenticate_access_token(token) do
      {:ok, auth} -> {:ok, auth}
      {:error, _reason} -> {:ok, nil}
    end
  end

  defp required_auth(nil), do: {:error, :unauthenticated}

  defp required_auth(token) do
    ApiAuth.authenticate_access_token(token)
  end

  defp policy(%{service_name: "hrafnsyn.v1.AuthService", method_name: method_name})
       when method_name in ["GetAuthStatus", "Login", "Refresh"] do
    if method_name == "GetAuthStatus" and ApiAuth.auth_required?(), do: :optional, else: :none
  end

  defp policy(%{service_name: "hrafnsyn.v1.AuthService", method_name: "RevokeAllSessions"}),
    do: :admin

  defp policy(%{service_name: "hrafnsyn.v1.AuthService"}), do: :authenticated

  defp policy(%{service_name: "hrafnsyn.v1.TrackingService"}) do
    if ApiAuth.auth_required?(), do: :authenticated, else: :optional
  end

  defp policy(%{service_name: "hrafnsyn.v1.TrackingIngress"}) do
    if ApiAuth.auth_required?(), do: :admin, else: :optional
  end

  defp policy(_stream), do: :none

  defp bearer_token(stream) do
    authorization =
      Map.get(stream.http_request_headers, "authorization") ||
        Map.get(GRPC.Stream.get_headers(stream), "authorization")

    case authorization do
      "Bearer " <> token -> token
      "bearer " <> token -> token
      _other -> nil
    end
  end
end
