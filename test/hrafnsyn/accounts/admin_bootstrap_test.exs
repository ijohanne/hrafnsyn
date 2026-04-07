defmodule Hrafnsyn.Accounts.AdminBootstrapTest do
  use Hrafnsyn.DataCase, async: false

  alias Hrafnsyn.Accounts
  alias Hrafnsyn.Accounts.AdminBootstrap

  import Hrafnsyn.AccountsFixtures

  setup do
    original_bootstrap_users = Application.get_env(:hrafnsyn, :bootstrap_users, [])

    on_exit(fn ->
      Application.put_env(:hrafnsyn, :bootstrap_users, original_bootstrap_users)
    end)

    :ok
  end

  test "creates configured bootstrap users on startup" do
    Application.put_env(:hrafnsyn, :bootstrap_users, [
      %{
        username: "ops-admin",
        password: "bootstrap secret",
        email: "ops@example.com",
        is_admin: true
      }
    ])

    AdminBootstrap.run_bootstrap()

    assert user = Accounts.get_user_by_username("ops-admin")
    assert user.email == "ops@example.com"
    assert user.is_admin
    assert user.confirmed_at
    assert Accounts.get_user_by_username_and_password("ops-admin", "bootstrap secret")
  end

  test "does not overwrite existing users when bootstrap runs again" do
    {:ok, existing_user} =
      Accounts.create_user_by_admin(%{
        username: "ops-admin",
        password: valid_user_password(),
        is_admin: true
      })

    existing_user_id = existing_user.id

    Application.put_env(:hrafnsyn, :bootstrap_users, [
      %{
        username: "ops-admin",
        password: "replacement secret",
        is_admin: true
      }
    ])

    AdminBootstrap.run_bootstrap()

    assert %Accounts.User{id: ^existing_user_id} = Accounts.get_user_by_username("ops-admin")
    assert Accounts.get_user_by_username_and_password("ops-admin", valid_user_password())
    refute Accounts.get_user_by_username_and_password("ops-admin", "replacement secret")
  end
end
