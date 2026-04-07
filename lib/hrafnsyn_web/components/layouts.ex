defmodule HrafnsynWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HrafnsynWeb, :html

  alias Hrafnsyn.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assign(assigns, :profile_initials, profile_initials(assigns.current_scope))

    ~H"""
    <header class="app-shell">
      <div class="brand-bar">
        <a href="/" class="brand-lockup">
          <img src={~p"/images/logo.svg"} width="48" height="48" alt="Hrafnsyn logo" />
          <div>
            <span>Hrafnsyn</span>
            <small>Unified maritime and aviation situational awareness</small>
          </div>
        </a>

        <nav class="top-nav">
          <.link navigate={~p"/"}>Live map</.link>
          <.link navigate={~p"/grpc"}>gRPC API</.link>
          <.link :if={Scope.admin?(@current_scope)} navigate={~p"/admin/users"}>Admin</.link>
          <.link :if={is_nil(@current_scope)} href={~p"/users/log-in"}>Log in</.link>

          <details
            :if={@current_scope}
            id="profile-menu"
            class="profile-menu"
            phx-hook="ProfileMenu"
            data-close-delay="180"
          >
            <summary class="profile-trigger">
              <span class="profile-trigger-copy">
                <strong>{@current_scope.user.username}</strong>
                <small>{if Scope.admin?(@current_scope), do: "Admin", else: "User"}</small>
              </span>
              <span class="profile-avatar" aria-hidden="true">{@profile_initials}</span>
            </summary>

            <div class="profile-dropdown">
              <.link href={~p"/users/settings"}>Change password</.link>
              <.link href={~p"/users/log-out"} method="delete">Log out</.link>
            </div>
          </details>
        </nav>
      </div>

      <div id="page-frame" class="page-frame" phx-hook="PreserveScroll">
        {render_slot(@inner_block)}
      </div>
    </header>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        timeout={0}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        timeout={0}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp profile_initials(%Scope{user: %{username: username}}) when is_binary(username) do
    username
    |> String.upcase()
    |> String.slice(0, 2)
  end

  defp profile_initials(_scope), do: "?"
end
