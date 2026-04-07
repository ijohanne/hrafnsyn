defmodule Hrafnsyn.Accounts.ApiJwt do
  @moduledoc false

  import Joken.Config

  alias Hrafnsyn.Accounts.User
  alias Hrafnsyn.GRPC.Config, as: GRPCConfig
  alias Joken.Signer

  @issuer "hrafnsyn"
  @access_type "access"
  @refresh_type "refresh"

  @type claims :: %{required(String.t()) => term()}

  @spec generate_access_token(User.t(), Ecto.UUID.t()) ::
          {:ok, binary(), claims()} | {:error, term()}
  def generate_access_token(%User{} = user, session_id) when is_binary(session_id) do
    extra_claims = %{
      "sub" => user.id,
      "sid" => session_id,
      "typ" => @access_type,
      "username" => user.username,
      "admin" => user.is_admin
    }

    generate_token(access_token_config(), extra_claims)
  end

  @spec generate_refresh_token(User.t(), Ecto.UUID.t()) ::
          {:ok, binary(), claims()} | {:error, term()}
  def generate_refresh_token(%User{} = user, session_id) when is_binary(session_id) do
    extra_claims = %{
      "sub" => user.id,
      "sid" => session_id,
      "typ" => @refresh_type
    }

    generate_token(refresh_token_config(), extra_claims)
  end

  @spec verify_access_token(binary()) :: {:ok, claims()} | {:error, term()}
  def verify_access_token(token) when is_binary(token) do
    verify_token(token, access_token_config())
  end

  @spec verify_refresh_token(binary()) :: {:ok, claims()} | {:error, term()}
  def verify_refresh_token(token) when is_binary(token) do
    verify_token(token, refresh_token_config())
  end

  @spec expires_at!(claims()) :: DateTime.t()
  def expires_at!(%{"exp" => unix_seconds}) when is_integer(unix_seconds) do
    DateTime.from_unix!(unix_seconds)
  end

  @spec issued_at!(claims()) :: DateTime.t()
  def issued_at!(%{"iat" => unix_seconds}) when is_integer(unix_seconds) do
    DateTime.from_unix!(unix_seconds)
  end

  defp generate_token(token_config, extra_claims) do
    case Joken.generate_claims(token_config, extra_claims) do
      {:ok, claims} -> Joken.encode_and_sign(claims, signer())
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_token(token, token_config) do
    with {:ok, claims} <- Joken.verify(token, signer()),
         {:ok, claims} <- Joken.validate(token_config, claims, %{}) do
      {:ok, claims}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp access_token_config do
    base_token_config(@access_type, GRPCConfig.access_token_ttl_seconds())
    |> add_claim("username", nil, &valid_string?/1)
    |> add_claim("admin", nil, &is_boolean/1)
  end

  defp refresh_token_config do
    base_token_config(@refresh_type, GRPCConfig.refresh_token_ttl_seconds())
  end

  defp base_token_config(token_type, ttl_seconds) do
    default_claims(skip: [:aud], default_exp: ttl_seconds, iss: @issuer)
    |> add_claim("sub", nil, &valid_string?/1)
    |> add_claim("sid", nil, &valid_string?/1)
    |> add_claim("typ", fn -> token_type end, &(&1 == token_type))
  end

  defp signer do
    Signer.create("HS256", GRPCConfig.jwt_secret())
  end

  defp valid_string?(value), do: is_binary(value) and value != ""
end
