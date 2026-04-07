defmodule HrafnsynWeb.UserTokensLive do
  use HrafnsynWeb, :live_view

  alias Hrafnsyn.Accounts.ApiAuth
  alias Hrafnsyn.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "API Tokens")
     |> assign(:issued_token_pair, nil)
     |> load_token_state()}
  end

  @impl true
  def handle_event("issue_token", _params, socket) do
    case ApiAuth.issue_token_pair(current_user(socket)) do
      {:ok, token_pair} ->
        {:noreply,
         socket
         |> assign(:issued_token_pair, token_pair)
         |> put_flash(
           :info,
           "New API token issued. Copy the refresh token now; it is only shown once."
         )
         |> load_token_state(token_pair.session.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not issue API token: #{inspect(reason)}")}
    end
  end

  def handle_event("revoke_own_session", %{"id" => session_id}, socket) do
    case ApiAuth.revoke_session(current_user(socket), session_id) do
      {:ok, _revoked_at} ->
        {:noreply,
         socket
         |> maybe_clear_issued_token_pair(session_id)
         |> put_flash(:info, "API token revoked.")
         |> load_token_state()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That API token is no longer available.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not revoke API token: #{inspect(reason)}")}
    end
  end

  def handle_event("revoke_admin_session", %{"id" => session_id}, socket) do
    case ApiAuth.revoke_any_session(current_user(socket), session_id) do
      {:ok, _revoked_at} ->
        {:noreply,
         socket
         |> maybe_clear_issued_token_pair(session_id)
         |> put_flash(:info, "API token revoked by admin.")
         |> load_token_state()}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Admin privileges are required for that action.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That API token is no longer available.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not revoke API token: #{inspect(reason)}")}
    end
  end

  def handle_event("revoke_all_sessions", _params, socket) do
    case ApiAuth.revoke_all_sessions(current_user(socket)) do
      {:ok, _revoked_at} ->
        {:noreply,
         socket
         |> assign(:issued_token_pair, nil)
         |> put_flash(:info, "All API tokens have been globally revoked.")
         |> load_token_state()}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Admin privileges are required for that action.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not revoke all API tokens: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class={["token-shell", !@admin? && "token-shell-single"]}>
        <div class="token-stack">
          <div class="panel">
            <div class="panel-title">
              <span>Issue API token</span>
              <span class="subtle">JWT access and refresh pair for gRPC clients</span>
            </div>
            <div class="token-card-copy">
              <p>
                Issue a new token pair for <strong>{@current_scope.user.username}</strong>. The refresh token is
                only shown here once, so copy it somewhere safe right away.
              </p>
              <.button variant="primary" phx-click="issue_token" data-role="issue-token">
                Issue new token
              </.button>
            </div>
          </div>

          <div :if={@issued_token_pair} class="panel token-secret-panel">
            <div class="panel-title">
              <span>Latest issued token pair</span>
              <span class="subtle">Shown once after creation</span>
            </div>
            <div class="token-secret-grid">
              <article class="token-secret-card">
                <div class="token-secret-head">
                  <strong>Access token</strong>
                  <span>{format_datetime(@issued_token_pair.access_token_expires_at)}</span>
                </div>
                <code>{@issued_token_pair.access_token}</code>
              </article>
              <article class="token-secret-card">
                <div class="token-secret-head">
                  <strong>Refresh token</strong>
                  <span>{format_datetime(@issued_token_pair.refresh_token_expires_at)}</span>
                </div>
                <code>{@issued_token_pair.refresh_token}</code>
              </article>
            </div>
          </div>

          <div class="panel">
            <div class="panel-title">
              <span>Your active API tokens</span>
              <span class="subtle">{length(@user_sessions)} active</span>
            </div>
            <div :if={@user_sessions == []} class="list-empty">
              No active API tokens yet.
            </div>
            <div :if={@user_sessions != []} class="token-list">
              <article
                :for={session <- @user_sessions}
                class="token-row"
                data-session-id={session.id}
              >
                <div class="token-row-copy">
                  <div class="token-row-head">
                    <strong>{short_id(session.id)}</strong>
                    <span :if={session.current} class="track-pill">NEW</span>
                  </div>
                  <dl class="token-meta-grid">
                    <div>
                      <dt>Created</dt>
                      <dd>{format_datetime(session.created_at)}</dd>
                    </div>
                    <div>
                      <dt>Last used</dt>
                      <dd>{format_datetime(session.last_used_at)}</dd>
                    </div>
                    <div>
                      <dt>Expires</dt>
                      <dd>{format_datetime(session.expires_at)}</dd>
                    </div>
                  </dl>
                </div>
                <div class="token-row-actions">
                  <.button
                    class="btn btn-soft btn-error btn-sm"
                    data-role="revoke-own-token"
                    data-session-id={session.id}
                    data-confirm="Revoke this API token?"
                    phx-click={JS.push("revoke_own_session", value: %{id: session.id})}
                  >
                    Revoke
                  </.button>
                </div>
              </article>
            </div>
          </div>
        </div>

        <div :if={@admin?} class="token-stack">
          <div class="panel">
            <div class="panel-title">
              <span>Admin controls</span>
              <span class="subtle">Global token management</span>
            </div>
            <div class="token-card-copy">
              <p>
                Global revocation invalidates every API token issued before the recorded cutoff. Use this when a
                wider credential reset is needed.
              </p>
              <p class="subtle">
                Last global revocation: <strong>{format_datetime(@global_revoked_at)}</strong>
              </p>
              <.button
                class="btn btn-error"
                data-role="revoke-all-tokens"
                data-confirm="Revoke all API tokens globally?"
                phx-click={JS.push("revoke_all_sessions")}
              >
                Revoke all API tokens
              </.button>
            </div>
          </div>

          <div class="panel">
            <div class="panel-title">
              <span>All active API tokens</span>
              <span class="subtle">{length(@admin_sessions)} active</span>
            </div>
            <div :if={@admin_sessions == []} class="list-empty">
              No active API tokens remain after the current revocation state.
            </div>
            <div :if={@admin_sessions != []} class="token-list">
              <article
                :for={session <- @admin_sessions}
                class="token-row token-row-admin"
                data-admin-session-id={session.id}
              >
                <div class="token-row-copy">
                  <div class="token-row-head">
                    <strong>{session.user.username}</strong>
                    <span class={[
                      "track-pill",
                      if(session.user.is_admin, do: "plane", else: "vessel")
                    ]}>
                      {if session.user.is_admin, do: "ADMIN", else: "USER"}
                    </span>
                  </div>
                  <p class="token-user-meta">
                    {session.user.email || "No email configured"}<span>Session {short_id(session.id)}</span>
                  </p>
                  <dl class="token-meta-grid">
                    <div>
                      <dt>Created</dt>
                      <dd>{format_datetime(session.created_at)}</dd>
                    </div>
                    <div>
                      <dt>Last used</dt>
                      <dd>{format_datetime(session.last_used_at)}</dd>
                    </div>
                    <div>
                      <dt>Expires</dt>
                      <dd>{format_datetime(session.expires_at)}</dd>
                    </div>
                  </dl>
                </div>
                <div class="token-row-actions">
                  <.button
                    class="btn btn-soft btn-error btn-sm"
                    data-role="revoke-admin-token"
                    data-session-id={session.id}
                    data-confirm="Revoke this user's API token?"
                    phx-click={JS.push("revoke_admin_session", value: %{id: session.id})}
                  >
                    Revoke
                  </.button>
                </div>
              </article>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_token_state(socket, current_session_id \\ nil) do
    user = current_user(socket)
    admin? = Scope.admin?(socket.assigns.current_scope)

    {admin_sessions, global_revoked_at} =
      if admin? do
        {:ok, sessions} = ApiAuth.list_all_sessions(user, current_session_id)
        {sessions, ApiAuth.global_revoked_at()}
      else
        {[], nil}
      end

    socket
    |> assign(:admin?, admin?)
    |> assign(:user_sessions, ApiAuth.list_sessions(user, current_session_id))
    |> assign(:admin_sessions, admin_sessions)
    |> assign(:global_revoked_at, global_revoked_at)
  end

  defp current_user(socket), do: socket.assigns.current_scope.user

  defp maybe_clear_issued_token_pair(socket, session_id) do
    case socket.assigns.issued_token_pair do
      %{session: %{id: ^session_id}} ->
        assign(socket, :issued_token_pair, nil)

      _other ->
        socket
    end
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp format_datetime(nil), do: "Never"

  defp format_datetime(%DateTime{} = value) do
    Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  end
end
