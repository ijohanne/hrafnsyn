defmodule HrafnsynWeb.Admin.UsersLive do
  use HrafnsynWeb, :live_view

  alias Hrafnsyn.Accounts
  alias Hrafnsyn.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin Users")
     |> assign(:users, Accounts.list_users())
     |> assign(:form, form_for_user(%User{}))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_admin_user(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("create", %{"user" => params}, socket) do
    case Accounts.create_user_by_admin(params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created.")
         |> assign(:users, Accounts.list_users())
         |> assign(:form, form_for_user(%User{}))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="admin-shell">
        <div class="panel">
          <div class="panel-title">
            <span>Create user</span>
            <span class="subtle">Passwords are local-only and hashed on save.</span>
          </div>
          <.form for={@form} phx-change="validate" phx-submit="create" class="admin-form">
            <.input field={@form[:email]} type="email" label="Email" />
            <.input field={@form[:password]} type="password" label="Password" />
            <.input field={@form[:is_admin]} type="checkbox" label="Admin access" />
            <.button>Create user</.button>
          </.form>
        </div>

        <div class="panel">
          <div class="panel-title">
            <span>Existing users</span>
            <span class="subtle">{length(@users)} total</span>
          </div>
          <div class="user-list">
            <article :for={user <- @users} class="user-row">
              <div>
                <strong>{user.email}</strong>
                <span>{if user.confirmed_at, do: "confirmed", else: "pending"}</span>
              </div>
              <span class={["track-pill", if(user.is_admin, do: "plane", else: "vessel")]}>
                {if user.is_admin, do: "ADMIN", else: "READONLY"}
              </span>
            </article>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp form_for_user(user) do
    user
    |> Accounts.change_admin_user()
    |> to_form()
  end
end
