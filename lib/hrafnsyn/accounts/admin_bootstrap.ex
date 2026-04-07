defmodule Hrafnsyn.Accounts.AdminBootstrap do
  @moduledoc """
  Creates initial users when bootstrap credentials are configured.
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
    run_bootstrap()
    {:noreply, state}
  end

  def run_bootstrap do
    bootstrap_users()
    |> Enum.each(&Accounts.ensure_bootstrap_admin/1)
  end

  defp bootstrap_users do
    case Application.get_env(:hrafnsyn, :bootstrap_users, []) do
      [] ->
        case legacy_bootstrap_user() do
          nil -> []
          user -> [user]
        end

      users when is_list(users) ->
        users
    end
  end

  defp legacy_bootstrap_user do
    cond do
      legacy_bootstrap_hash_attrs() != nil ->
        legacy_bootstrap_hash_attrs()

      legacy_bootstrap_password_attrs() != nil ->
        legacy_bootstrap_password_attrs()

      true ->
        nil
    end
  end

  defp legacy_bootstrap_hash_attrs do
    with username when is_binary(username) and username != "" <- legacy_bootstrap_username(),
         password_hash when is_binary(password_hash) and password_hash != "" <-
           System.get_env("BOOTSTRAP_ADMIN_PASSWORD_HASH") do
      %{
        username: username,
        email: System.get_env("BOOTSTRAP_ADMIN_EMAIL"),
        hashed_password: password_hash,
        is_admin: true,
        confirmed_at: DateTime.utc_now(:second)
      }
    end
  end

  defp legacy_bootstrap_password_attrs do
    with username when is_binary(username) and username != "" <- legacy_bootstrap_username(),
         password when is_binary(password) and password != "" <-
           System.get_env("BOOTSTRAP_ADMIN_PASSWORD") do
      %{
        username: username,
        email: System.get_env("BOOTSTRAP_ADMIN_EMAIL"),
        password: password,
        is_admin: true
      }
    end
  end

  defp legacy_bootstrap_username do
    System.get_env("BOOTSTRAP_ADMIN_USERNAME") || System.get_env("BOOTSTRAP_ADMIN_EMAIL")
  end
end
