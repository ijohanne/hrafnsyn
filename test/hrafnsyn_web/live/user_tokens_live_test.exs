defmodule HrafnsynWeb.UserTokensLiveTest do
  use HrafnsynWeb.ConnCase, async: false

  import Hrafnsyn.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Hrafnsyn.Accounts.ApiAuth
  alias Hrafnsyn.Accounts.ApiSession
  alias Hrafnsyn.Accounts.User
  alias Hrafnsyn.Repo

  test "guests are redirected to the login page", %{conn: conn} do
    conn = get(conn, ~p"/users/tokens")

    assert redirected_to(conn) == ~p"/users/log-in"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "You must log in to access this page."
  end

  test "users can issue and revoke their own API tokens", %{conn: conn} do
    user = user_fixture() |> set_password()
    {:ok, existing_pair} = ApiAuth.issue_token_pair(user)

    {:ok, view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/tokens")

    assert html =~ "Issue API token"
    assert html =~ "Your active API tokens"
    refute html =~ "Admin controls"
    assert has_element?(view, "[data-session-id='#{existing_pair.session.id}']")

    token_count_before = Repo.aggregate(ApiSession, :count, :id)

    view
    |> element("[data-role='issue-token']")
    |> render_click()

    assert render(view) =~ "New API token issued."
    assert Repo.aggregate(ApiSession, :count, :id) == token_count_before + 1
    assert render(view) =~ "Latest issued token pair"

    view
    |> element("[data-role='revoke-own-token'][data-session-id='#{existing_pair.session.id}']")
    |> render_click()

    refute has_element?(view, "[data-session-id='#{existing_pair.session.id}']")
    assert %ApiSession{revoked_at: %DateTime{}} = Repo.get!(ApiSession, existing_pair.session.id)
  end

  test "admins can inspect all tokens, revoke one, and revoke all globally", %{conn: conn} do
    admin = admin_user_fixture() |> set_password()
    user = user_fixture() |> set_password()
    {:ok, admin_pair} = ApiAuth.issue_token_pair(admin)
    {:ok, user_pair} = ApiAuth.issue_token_pair(user)

    {:ok, view, html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/users/tokens")

    assert html =~ "Admin controls"
    assert has_element?(view, "[data-admin-session-id='#{user_pair.session.id}']")
    assert render(view) =~ user.username

    view
    |> element("[data-role='revoke-admin-token'][data-session-id='#{user_pair.session.id}']")
    |> render_click()

    assert %ApiSession{revoked_at: %DateTime{}} = Repo.get!(ApiSession, user_pair.session.id)
    refute has_element?(view, "[data-admin-session-id='#{user_pair.session.id}']")

    view
    |> element("[data-role='revoke-all-tokens']")
    |> render_click()

    assert render(view) =~ "All API tokens have been globally revoked."
    assert ApiAuth.global_revoked_at()
    refute has_element?(view, "[data-admin-session-id='#{admin_pair.session.id}']")
  end

  defp admin_user_fixture do
    {:ok, admin} =
      %{
        username: unique_user_username(),
        email: unique_user_email(),
        password: valid_user_password(),
        is_admin: true
      }
      |> Hrafnsyn.Accounts.create_user_by_admin()

    %User{admin | authenticated_at: DateTime.utc_now(:second)}
  end
end
