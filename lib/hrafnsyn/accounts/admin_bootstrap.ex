defmodule Hrafnsyn.Accounts.AdminBootstrap do
  @moduledoc """
  Creates an initial admin user when bootstrap credentials are configured.
  """

  use GenServer

  alias Hrafnsyn.Accounts

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    send(self(), :bootstrap)
    {:ok, state}
  end

  @impl true
  def handle_info(:bootstrap, state) do
    maybe_bootstrap_admin()
    {:noreply, state}
  end

  defp maybe_bootstrap_admin do
    cond do
      bootstrap_hash_attrs() != nil ->
        Accounts.ensure_bootstrap_admin(bootstrap_hash_attrs())

      bootstrap_password_attrs() != nil ->
        maybe_create_admin_from_password(bootstrap_password_attrs())

      true ->
        :ok
    end
  end

  defp bootstrap_hash_attrs do
    with email when is_binary(email) and email != "" <- System.get_env("BOOTSTRAP_ADMIN_EMAIL"),
         password_hash when is_binary(password_hash) and password_hash != "" <-
           System.get_env("BOOTSTRAP_ADMIN_PASSWORD_HASH") do
      %{
        email: email,
        hashed_password: password_hash,
        is_admin: true,
        confirmed_at: DateTime.utc_now(:second)
      }
    end
  end

  defp bootstrap_password_attrs do
    with email when is_binary(email) and email != "" <- System.get_env("BOOTSTRAP_ADMIN_EMAIL"),
         password when is_binary(password) and password != "" <-
           System.get_env("BOOTSTRAP_ADMIN_PASSWORD") do
      %{
        email: email,
        password: password,
        is_admin: true
      }
    end
  end

  defp maybe_create_admin_from_password(%{email: email} = attrs) do
    case Accounts.get_user_by_email(email) do
      nil -> Accounts.create_user_by_admin(attrs)
      _user -> :ok
    end
  end
end
