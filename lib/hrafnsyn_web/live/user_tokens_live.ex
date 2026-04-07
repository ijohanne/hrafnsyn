defmodule HrafnsynWeb.UserTokensLive do
  use HrafnsynWeb, :live_view

  alias Hrafnsyn.Accounts.{ApiAuth, ApiSession}
  alias Hrafnsyn.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "API Tokens")
     |> assign(:issued_token_pair, nil)
     |> assign(:editing_session_id, nil)
     |> assign(:rename_form, rename_form())
     |> assign(:issue_form, issue_form())
     |> load_token_state()}
  end

  @impl true
  def handle_event("validate_issue_token", %{"issue_token" => params}, socket) do
    {:noreply, assign(socket, :issue_form, issue_form(params, :validate))}
  end

  def handle_event("issue_token", %{"issue_token" => params}, socket) do
    case ApiAuth.issue_token_pair(current_user(socket), params) do
      {:ok, token_pair} ->
        {:noreply,
         socket
         |> assign(:issued_token_pair, token_pair)
         |> assign(:issue_form, issue_form())
         |> put_flash(
           :info,
           "New API token issued. Copy the refresh token now; it is only shown once."
         )
         |> load_token_state(token_pair.session.id)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :issue_form, to_form(%{changeset | action: :insert}, as: :issue_token))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not issue API token: #{inspect(reason)}")}
    end
  end

  def handle_event("start_rename", %{"id" => session_id, "name" => name}, socket) do
    {:noreply,
     socket
     |> assign(:editing_session_id, session_id)
     |> assign(:rename_form, rename_form(%{"name" => name}))}
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_session_id, nil)
     |> assign(:rename_form, rename_form())}
  end

  def handle_event("validate_rename_token", %{"rename_token" => params}, socket) do
    {:noreply, assign(socket, :rename_form, rename_form(params, :validate))}
  end

  def handle_event(
        "rename_token",
        %{"_session_id" => session_id, "rename_token" => params},
        socket
      ) do
    case ApiAuth.rename_session(current_user(socket), session_id, params) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign(:editing_session_id, nil)
         |> assign(:rename_form, rename_form())
         |> put_flash(:info, "API token renamed.")
         |> load_token_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:editing_session_id, session_id)
         |> assign(:rename_form, to_form(%{changeset | action: :validate}, as: :rename_token))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:editing_session_id, nil)
         |> assign(:rename_form, rename_form())
         |> put_flash(:error, "That API token is no longer available.")
         |> load_token_state()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not rename API token: #{inspect(reason)}")}
    end
  end

  def handle_event("revoke_own_session", %{"id" => session_id}, socket) do
    case ApiAuth.revoke_session(current_user(socket), session_id) do
      {:ok, _revoked_at} ->
        {:noreply,
         socket
         |> maybe_clear_issued_token_pair(session_id)
         |> maybe_clear_rename_state(session_id)
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
      <section class="token-shell">
        <header class="token-hero">
          <div class="token-hero-copy">
            <div class="token-kicker">Credential control deck</div>
            <h1>API token management</h1>
            <p class="token-lead">
              Issue gRPC credentials, track active sessions, and lock down exposure from one place.
              Refresh secrets are shown once, revocations land immediately, and admin controls stay
              clearly separated from personal access management.
            </p>

            <dl class="token-stat-grid">
              <div>
                <dt>Operator</dt>
                <dd>{@current_scope.user.username}</dd>
              </div>
              <div>
                <dt>Your active tokens</dt>
                <dd>{length(@user_sessions)}</dd>
              </div>
              <div :if={@admin?}>
                <dt>Fleet-wide active</dt>
                <dd>{length(@admin_sessions)}</dd>
              </div>
              <div :if={@admin?}>
                <dt>Last global reset</dt>
                <dd>{format_datetime(@global_revoked_at)}</dd>
              </div>
            </dl>
          </div>

          <div class="token-hero-board">
            <div class="token-board-head">
              <span class="token-board-chip">Security posture</span>
              <span class="token-board-chip token-board-chip-soft">
                {if @admin?, do: "Admin deck", else: "Personal deck"}
              </span>
            </div>

            <ol class="token-board-list">
              <li>
                <strong>Issue a pair</strong>
                <span>Generate access and refresh credentials for a new client session.</span>
              </li>
              <li>
                <strong>Copy once</strong>
                <span>Refresh secrets are exposed only at creation time on this page.</span>
              </li>
              <li :if={@admin?}>
                <strong>Supervise globally</strong>
                <span>
                  Inspect active sessions across users and cut off the full fleet when needed.
                </span>
              </li>
              <li :if={!@admin?}>
                <strong>Self-manage safely</strong>
                <span>Review your own sessions without stepping into admin-only controls.</span>
              </li>
            </ol>
          </div>
        </header>

        <div class={["token-content", !@admin? && "token-content-single"]}>
          <div class="token-stack">
            <section class="token-panel token-issue-panel">
              <div class="token-section-head">
                <div>
                  <div class="token-section-kicker">Issue</div>
                  <h2>Mint a fresh token pair</h2>
                </div>
                <span class="token-section-label">JWT access + refresh</span>
              </div>

              <div class="token-issue-grid">
                <div class="token-card-copy">
                  <p>
                    Issue a new token pair for <strong>{@current_scope.user.username}</strong>. Use it for CLI
                    tools, app-native clients, or any environment that needs gRPC access tied to your account.
                  </p>
                  <p class="subtle">
                    The refresh token is only shown once after creation, so treat the next reveal as your handoff moment.
                  </p>
                </div>

                <div class="token-action-card">
                  <span class="token-action-badge">Ready</span>
                  <strong>Provision a new client session</strong>
                  <p>Creates a fresh access token immediately and tracks the session below.</p>
                  <.form
                    for={@issue_form}
                    id="issue-token-form"
                    as={:issue_token}
                    phx-change="validate_issue_token"
                    phx-submit="issue_token"
                    class="token-issue-form"
                  >
                    <.input
                      field={@issue_form[:name]}
                      type="text"
                      label="Token name"
                      placeholder="Bridge iPad, Ops laptop, Watchtower"
                    />
                    <.button variant="primary" data-role="issue-token">
                      Issue new token
                    </.button>
                  </.form>
                </div>
              </div>
            </section>

            <section :if={@issued_token_pair} class="token-panel token-secret-panel">
              <div class="token-section-head">
                <div>
                  <div class="token-section-kicker">Reveal</div>
                  <h2>Latest issued token pair</h2>
                </div>
                <span class="token-section-label">Shown once</span>
              </div>

              <div class="token-secret-grid">
                <article class="token-secret-card">
                  <div class="token-secret-head">
                    <strong>Access token</strong>
                    <span>Expires {format_datetime(@issued_token_pair.access_token_expires_at)}</span>
                  </div>
                  <code>{@issued_token_pair.access_token}</code>
                </article>
                <article class="token-secret-card token-secret-card-refresh">
                  <div class="token-secret-head">
                    <strong>Refresh token</strong>
                    <span>
                      Expires {format_datetime(@issued_token_pair.refresh_token_expires_at)}
                    </span>
                  </div>
                  <code>{@issued_token_pair.refresh_token}</code>
                </article>
              </div>
            </section>

            <section class="token-panel">
              <div class="token-section-head">
                <div>
                  <div class="token-section-kicker">Personal vault</div>
                  <h2>Your active API tokens</h2>
                </div>
                <span class="token-section-label">{length(@user_sessions)} active</span>
              </div>

              <div :if={@user_sessions == []} class="token-empty-state">
                <strong>No active tokens yet.</strong>
                <p>
                  Issue your first token pair to authorize a gRPC client and start tracking it here.
                </p>
              </div>

              <div :if={@user_sessions != []} class="token-list">
                <article
                  :for={session <- @user_sessions}
                  class="token-row"
                  data-session-id={session.id}
                >
                  <div class="token-row-copy">
                    <div class="token-row-head">
                      <strong>{session.name}</strong>
                      <span :if={session.current} class="track-pill">NEW</span>
                    </div>
                    <p class="token-user-meta">
                      <span>Session {short_id(session.id)}</span>
                    </p>
                    <p class="token-row-summary">
                      {if session.current,
                        do: "This is the newest session issued from the web UI.",
                        else: "Existing client session still inside its validity window."}
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

                    <div :if={@editing_session_id == session.id} class="token-rename-card">
                      <.form
                        for={@rename_form}
                        id={"rename-token-form-#{session.id}"}
                        as={:rename_token}
                        phx-change="validate_rename_token"
                        phx-submit="rename_token"
                        class="token-inline-form"
                      >
                        <input type="hidden" name="_session_id" value={session.id} />
                        <.input
                          field={@rename_form[:name]}
                          type="text"
                          label="Rename token"
                          placeholder="New token label"
                        />
                        <div class="token-inline-actions">
                          <.button class="btn btn-primary btn-sm" data-role="save-token-rename">
                            Save name
                          </.button>
                          <.button
                            type="button"
                            class="btn btn-soft btn-sm"
                            phx-click="cancel_rename"
                            data-role="cancel-token-rename"
                          >
                            Cancel
                          </.button>
                        </div>
                      </.form>
                    </div>
                  </div>
                  <div class="token-row-actions">
                    <.button
                      :if={@editing_session_id != session.id}
                      class="btn btn-soft btn-sm"
                      data-role="rename-own-token"
                      data-session-id={session.id}
                      phx-click="start_rename"
                      phx-value-id={session.id}
                      phx-value-name={session.name}
                    >
                      Rename
                    </.button>
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
            </section>
          </div>

          <aside :if={@admin?} class="token-stack token-admin-rail">
            <section class="token-panel token-admin-panel">
              <div class="token-section-head">
                <div>
                  <div class="token-section-kicker">Admin rail</div>
                  <h2>Global controls</h2>
                </div>
                <span class="token-section-label">System-wide</span>
              </div>

              <div class="token-card-copy">
                <p>
                  Global revocation invalidates every API token issued before the recorded cutoff. Use it when a
                  wider credential reset is needed across clients or environments.
                </p>
              </div>

              <div class="token-admin-callout">
                <span>Last global revocation</span>
                <strong>{format_datetime(@global_revoked_at)}</strong>
              </div>

              <.button
                class="btn btn-error"
                data-role="revoke-all-tokens"
                data-confirm="Revoke all API tokens globally?"
                phx-click={JS.push("revoke_all_sessions")}
              >
                Revoke all API tokens
              </.button>
            </section>

            <section class="token-panel token-admin-list-panel">
              <div class="token-section-head">
                <div>
                  <div class="token-section-kicker">Registry</div>
                  <h2>All active API tokens</h2>
                </div>
                <span class="token-section-label">{length(@admin_sessions)} active</span>
              </div>

              <div :if={@admin_sessions == []} class="token-empty-state">
                <strong>No active API tokens remain.</strong>
                <p>The current revocation cutoff already excludes every tracked session.</p>
              </div>

              <div :if={@admin_sessions != []} class="token-list">
                <article
                  :for={session <- @admin_sessions}
                  class="token-row token-row-admin"
                  data-admin-session-id={session.id}
                >
                  <div class="token-row-copy">
                    <div class="token-row-head">
                      <strong>{session.name}</strong>
                      <span class={[
                        "track-pill",
                        if(session.user.is_admin, do: "plane", else: "vessel")
                      ]}>
                        {if session.user.is_admin, do: "ADMIN", else: "USER"}
                      </span>
                    </div>
                    <p class="token-user-meta">
                      <span>{session.user.username}</span>
                      <span>{session.user.email || "No email configured"}</span>
                      <span>Session {short_id(session.id)}</span>
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
            </section>
          </aside>
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

  defp maybe_clear_rename_state(socket, session_id) do
    if socket.assigns.editing_session_id == session_id do
      socket
      |> assign(:editing_session_id, nil)
      |> assign(:rename_form, rename_form())
    else
      socket
    end
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp format_datetime(nil), do: "Never"

  defp format_datetime(%DateTime{} = value) do
    Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  end

  defp issue_form(attrs \\ %{}, action \\ nil) do
    %ApiSession{}
    |> ApiSession.rename_changeset(attrs)
    |> maybe_put_action(action)
    |> to_form(as: :issue_token)
  end

  defp rename_form(attrs \\ %{}, action \\ nil) do
    %ApiSession{}
    |> ApiSession.rename_changeset(attrs)
    |> maybe_put_action(action)
    |> to_form(as: :rename_token)
  end

  defp maybe_put_action(changeset, nil), do: changeset
  defp maybe_put_action(changeset, action), do: Map.put(changeset, :action, action)
end
