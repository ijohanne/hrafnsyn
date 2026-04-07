defmodule Hrafnsyn.GRPC.AuthServer do
  @moduledoc false

  use GRPC.Server, service: Hrafnsyn.V1.AuthService.Service

  alias Hrafnsyn.Accounts.ApiAuth
  alias Hrafnsyn.GRPC.Helpers

  def get_auth_status(_request, stream) do
    auth = Helpers.auth_context(stream)

    %Hrafnsyn.V1.AuthStatus{
      auth_required: ApiAuth.auth_required?(),
      authenticated: not is_nil(auth),
      access_token_ttl_seconds: ApiAuth.access_token_ttl_seconds(),
      refresh_token_ttl_seconds: ApiAuth.refresh_token_ttl_seconds(),
      current_user: auth && Helpers.user_profile(auth.user)
    }
  end

  def login(%Hrafnsyn.V1.LoginRequest{username: username, password: password}, _stream) do
    case ApiAuth.login(username, password) do
      {:ok, token_pair} ->
        Helpers.token_pair(token_pair)

      {:error, :invalid_credentials} ->
        raise GRPC.RPCError, status: :unauthenticated, message: "Invalid username or password"

      {:error, reason} ->
        raise GRPC.RPCError, status: :internal, message: "Login failed: #{inspect(reason)}"
    end
  end

  def refresh(%Hrafnsyn.V1.RefreshRequest{refresh_token: refresh_token}, _stream) do
    case ApiAuth.refresh(refresh_token) do
      {:ok, token_pair} ->
        Helpers.token_pair(token_pair)

      {:error, :revoked} ->
        raise GRPC.RPCError, status: :unauthenticated, message: "Refresh token has been revoked"

      {:error, _reason} ->
        raise GRPC.RPCError, status: :unauthenticated, message: "Refresh token is invalid"
    end
  end

  def list_sessions(_request, stream) do
    auth = Helpers.auth_context(stream)

    %Hrafnsyn.V1.ListSessionsResponse{
      sessions:
        auth.user
        |> ApiAuth.list_sessions(auth.session.id)
        |> Enum.map(&Helpers.session_info/1)
    }
  end

  def revoke_session(%Hrafnsyn.V1.RevokeSessionRequest{session_id: session_id}, stream) do
    auth = Helpers.auth_context(stream)

    case ApiAuth.revoke_session(auth.user, session_id) do
      {:ok, revoked_at} ->
        %Hrafnsyn.V1.RevocationResponse{
          scope: "session",
          session_id: session_id,
          revoked_at: Helpers.timestamp(revoked_at)
        }

      {:error, :not_found} ->
        raise GRPC.RPCError, status: :not_found, message: "Session was not found"

      {:error, reason} ->
        raise GRPC.RPCError, status: :internal, message: "Revocation failed: #{inspect(reason)}"
    end
  end

  def revoke_all_sessions(_request, stream) do
    auth = Helpers.auth_context(stream)

    case ApiAuth.revoke_all_sessions(auth.user) do
      {:ok, revoked_at} ->
        %Hrafnsyn.V1.RevocationResponse{
          scope: "global",
          revoked_at: Helpers.timestamp(revoked_at)
        }

      {:error, :forbidden} ->
        raise GRPC.RPCError, status: :permission_denied, message: "Admin privileges are required"

      {:error, reason} ->
        raise GRPC.RPCError,
          status: :internal,
          message: "Global revocation failed: #{inspect(reason)}"
    end
  end
end
