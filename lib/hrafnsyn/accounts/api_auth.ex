defmodule Hrafnsyn.Accounts.ApiAuth do
  @moduledoc """
  Runtime-aware JWT session management for gRPC clients.
  """

  import Ecto.Query, warn: false

  alias Hrafnsyn.Accounts
  alias Hrafnsyn.Accounts.{ApiAuthState, ApiJwt, ApiSession, Scope, User}
  alias Hrafnsyn.GRPC.Config, as: GRPCConfig
  alias Hrafnsyn.Repo

  @state_name "global"

  @type auth_context :: %{
          claims: map(),
          scope: Scope.t(),
          session: ApiSession.t(),
          user: User.t()
        }

  @spec auth_required?() :: boolean()
  def auth_required? do
    not Application.get_env(:hrafnsyn, :public_readonly?, true)
  end

  @spec access_token_ttl_seconds() :: pos_integer()
  def access_token_ttl_seconds, do: GRPCConfig.access_token_ttl_seconds()

  @spec refresh_token_ttl_seconds() :: pos_integer()
  def refresh_token_ttl_seconds, do: GRPCConfig.refresh_token_ttl_seconds()

  @spec login(binary(), binary()) :: {:ok, map()} | {:error, :invalid_credentials | term()}
  def login(username, password) when is_binary(username) and is_binary(password) do
    with {:ok, user} <- authenticate_username_password(username, password) do
      create_session(user)
    end
  end

  @spec authenticate_access_token(binary()) :: {:ok, auth_context()} | {:error, atom()}
  def authenticate_access_token(token) when is_binary(token) do
    with {:ok, claims} <- ApiJwt.verify_access_token(token),
         {:ok, session} <- get_active_session(claims["sid"]),
         :ok <- ensure_not_globally_revoked(claims),
         %User{} = user <- session.user do
      {:ok, %{claims: claims, scope: Scope.for_user(user), session: session, user: user}}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :user_not_found}
      _other -> {:error, :invalid_token}
    end
  end

  @spec refresh(binary()) :: {:ok, map()} | {:error, atom()}
  def refresh(token) when is_binary(token) do
    case ApiJwt.verify_refresh_token(token) do
      {:ok, claims} ->
        Repo.transact(fn -> refresh_session(claims) end)

      _other ->
        {:error, :invalid_token}
    end
  end

  @spec list_sessions(User.t(), Ecto.UUID.t() | nil) :: [map()]
  def list_sessions(%User{} = user, current_session_id \\ nil) do
    ApiSession
    |> where([session], session.user_id == ^user.id)
    |> where([session], is_nil(session.revoked_at))
    |> where([session], session.expires_at > ^DateTime.utc_now(:second))
    |> order_by([session], desc: session.inserted_at)
    |> Repo.all()
    |> Enum.map(&session_to_map(&1, current_session_id))
  end

  @spec revoke_session(User.t(), Ecto.UUID.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  def revoke_session(%User{} = user, session_id) when is_binary(session_id) do
    Repo.transact(fn -> do_revoke_session(user.id, session_id) end)
  end

  @spec revoke_all_sessions(User.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  def revoke_all_sessions(%User{is_admin: true}) do
    revoked_at = DateTime.utc_now(:second)

    attrs = %{name: @state_name, global_revoked_at: revoked_at}

    %ApiAuthState{name: @state_name}
    |> ApiAuthState.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [global_revoked_at: revoked_at, updated_at: revoked_at]],
      conflict_target: :name
    )
    |> case do
      {:ok, _state} -> {:ok, revoked_at}
      {:error, _changeset} -> {:error, :revocation_failed}
    end
  end

  def revoke_all_sessions(%User{}), do: {:error, :forbidden}

  @spec global_revoked_at() :: DateTime.t() | nil
  def global_revoked_at do
    case Repo.get(ApiAuthState, @state_name) do
      %ApiAuthState{global_revoked_at: revoked_at} -> revoked_at
      nil -> nil
    end
  end

  defp authenticate_username_password(username, password) do
    case Accounts.get_user_by_username_and_password(username, password) do
      %User{} = user -> {:ok, user}
      _other -> {:error, :invalid_credentials}
    end
  end

  defp create_session(%User{} = user) do
    Repo.transact(fn ->
      session_id = Ecto.UUID.generate()

      with {:ok, refresh_token, refresh_claims} <-
             ApiJwt.generate_refresh_token(user, session_id),
           {:ok, session} <- insert_session(user, session_id, refresh_claims),
           {:ok, access_token, access_claims} <- ApiJwt.generate_access_token(user, session.id) do
        {:ok,
         build_token_pair(
           user,
           session,
           access_token,
           access_claims,
           refresh_token,
           refresh_claims
         )}
      else
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp rotate_session_tokens(%ApiSession{} = session, %User{} = user) do
    with {:ok, refresh_token, refresh_claims} <- ApiJwt.generate_refresh_token(user, session.id),
         {:ok, access_token, access_claims} <- ApiJwt.generate_access_token(user, session.id),
         {:ok, session} <- update_refresh_session(session, refresh_claims) do
      {:ok,
       build_token_pair(user, session, access_token, access_claims, refresh_token, refresh_claims)}
    else
      {:error, _reason} = error -> error
    end
  end

  defp refresh_session(claims) do
    with {:ok, session} <- get_active_session_for_update(claims["sid"]),
         :ok <- ensure_refresh_token_matches(session, claims),
         :ok <- ensure_not_globally_revoked(claims),
         %User{} = user <- session.user,
         {:ok, token_pair} <- rotate_session_tokens(session, user) do
      {:ok, token_pair}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :user_not_found}
      _other -> {:error, :invalid_token}
    end
  end

  defp insert_session(%User{} = user, session_id, refresh_claims) do
    now = DateTime.utc_now(:second)

    %ApiSession{}
    |> ApiSession.changeset(%{
      id: session_id,
      user_id: user.id,
      refresh_token_hash: hash_jti(refresh_claims["jti"]),
      last_used_at: now,
      expires_at: ApiJwt.expires_at!(refresh_claims)
    })
    |> Repo.insert()
  end

  defp update_refresh_session(%ApiSession{} = session, refresh_claims) do
    session
    |> ApiSession.changeset(%{
      refresh_token_hash: hash_jti(refresh_claims["jti"]),
      last_used_at: DateTime.utc_now(:second),
      expires_at: ApiJwt.expires_at!(refresh_claims)
    })
    |> Repo.update()
  end

  defp build_token_pair(user, session, access_token, access_claims, refresh_token, refresh_claims) do
    %{
      access_token: access_token,
      access_token_expires_at: ApiJwt.expires_at!(access_claims),
      refresh_token: refresh_token,
      refresh_token_expires_at: ApiJwt.expires_at!(refresh_claims),
      session: session_to_map(session, session.id),
      user: user_to_map(user)
    }
  end

  defp get_active_session(session_id) do
    ApiSession
    |> where([session], session.id == ^session_id)
    |> where([session], is_nil(session.revoked_at))
    |> where([session], session.expires_at > ^DateTime.utc_now(:second))
    |> preload(:user)
    |> Repo.one()
    |> case do
      %ApiSession{} = session -> {:ok, session}
      nil -> {:error, :invalid_token}
    end
  end

  defp get_active_session_for_update(session_id) do
    ApiSession
    |> where([session], session.id == ^session_id)
    |> where([session], is_nil(session.revoked_at))
    |> where([session], session.expires_at > ^DateTime.utc_now(:second))
    |> preload(:user)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %ApiSession{} = session -> {:ok, session}
      nil -> {:error, :invalid_token}
    end
  end

  defp fetch_revokeable_session(user_id, session_id) do
    ApiSession
    |> where([session], session.id == ^session_id and session.user_id == ^user_id)
    |> where([session], is_nil(session.revoked_at))
    |> Repo.one()
  end

  defp do_revoke_session(user_id, session_id) do
    case fetch_revokeable_session(user_id, session_id) do
      nil ->
        {:error, :not_found}

      %ApiSession{} = session ->
        update_revoked_session(session)
    end
  end

  defp update_revoked_session(%ApiSession{} = session) do
    revoked_at = DateTime.utc_now(:second)

    case Repo.update(ApiSession.changeset(session, %{revoked_at: revoked_at})) do
      {:ok, _session} -> {:ok, revoked_at}
      {:error, _changeset} -> {:error, :not_found}
    end
  end

  defp ensure_refresh_token_matches(%ApiSession{} = session, %{"jti" => jti}) do
    if session.refresh_token_hash == hash_jti(jti) do
      :ok
    else
      {:error, :invalid_token}
    end
  end

  defp ensure_not_globally_revoked(claims) do
    case global_revoked_at() do
      nil ->
        :ok

      %DateTime{} = revoked_at ->
        if DateTime.compare(ApiJwt.issued_at!(claims), revoked_at) == :gt do
          :ok
        else
          {:error, :revoked}
        end
    end
  end

  defp hash_jti(jti) when is_binary(jti), do: :crypto.hash(:sha256, jti)

  defp user_to_map(%User{} = user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      is_admin: user.is_admin
    }
  end

  defp session_to_map(%ApiSession{} = session, current_session_id) do
    %{
      id: session.id,
      current: session.id == current_session_id,
      created_at: session.inserted_at,
      last_used_at: session.last_used_at,
      expires_at: session.expires_at,
      revoked_at: session.revoked_at
    }
  end
end
