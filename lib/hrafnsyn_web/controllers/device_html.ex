defmodule HrafnsynWeb.DeviceHTML do
  use HrafnsynWeb, :html

  alias Hrafnsyn.Devices

  def index(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="device-workspace" aria-labelledby="device-page-title">
        <header class="device-page-heading">
          <div>
            <h1 id="device-page-title">Device invitations</h1>
            <p>Collect iPhone and iPad identifiers for private app builds, without a cable.</p>
          </div>
          <a href="/users/devices" class="device-button device-button-secondary">Refresh status</a>
        </header>

        <section class="device-app" aria-labelledby="device-app-title">
          <div class="device-app-download">
            <div>
              <h2 id="device-app-title">iPhone &amp; iPad app</h2>
              <%= case @mobile_build do %>
                <% {:ok, build} -> %>
                  <p class="device-app-meta">
                    Hrafnsyn.ipa · {format_size(build.size)}<br />
                    Updated {format_datetime(build.uploaded_at)}
                  </p>
                <% {:error, :not_found} -> %>
                  <p>No build available yet. An administrator can upload one here.</p>
                <% _ -> %>
                  <p>The download is temporarily unavailable. Please try again later.</p>
              <% end %>
            </div>
            <div
              :if={match?({:ok, _}, @mobile_build)}
              class="device-app-actions"
            >
              <a href={~p"/users/devices/install"} class="device-button device-button-primary">
                <.icon name="hero-device-phone-mobile" class="size-4" /> Install on iPhone or iPad
              </a>
              <a href={~p"/users/devices/app.ipa"} class="device-button device-button-secondary">
                <.icon name="hero-arrow-down-tray" class="size-4" /> Download IPA
              </a>
            </div>
          </div>
          <p class="device-help device-app-install-note">
            Open the install page in Safari on a registered device included in this build.
            No computer or cable is needed. The IPA download is also available for Mac installation.
          </p>

          <details :if={Hrafnsyn.Accounts.Scope.admin?(@current_scope)} class="device-app-admin">
            <summary>
              {if match?({:ok, _}, @mobile_build), do: "Replace IPA", else: "Upload IPA"}
            </summary>
            <.form
              for={%{}}
              action={~p"/admin/mobile-build"}
              method="post"
              multipart
              id="mobile-build-upload"
              data-ipa-upload
            >
              <div class="device-field">
                <label for="mobile-build-file">Signed IPA file</label>
                <input
                  id="mobile-build-file"
                  type="file"
                  name="ipa"
                  accept=".ipa"
                  required
                  aria-describedby="mobile-build-help"
                />
                <p id="mobile-build-help" class="device-help">
                  Up to 250 MiB. Every signed-in user can download it. Uploading replaces the
                  current file; no previous versions are kept. Export a signed Ad Hoc build
                  that includes your testers’ devices.
                </p>
              </div>
              <button type="submit" class="device-button device-button-secondary">Publish IPA</button>
              <p class="device-help" data-ipa-upload-status role="status" aria-live="polite"></p>
            </.form>
          </details>
        </section>

        <div class="device-management">
          <section class="device-create" aria-labelledby="device-create-title">
            <h2 id="device-create-title">Invite a device</h2>
            <p>
              Make one link for each iPhone or iPad. Your friend opens it in Safari on that device.
            </p>

            <.form for={@form} action="/users/devices" method="post" id="device-invitation-form">
              <div class="device-field">
                <label for="invitation-label">Device label</label>
                <input
                  id="invitation-label"
                  name={@form[:label].name}
                  value={@form[:label].value}
                  type="text"
                  maxlength="80"
                  required
                  autocomplete="off"
                  placeholder="Alex’s iPhone"
                  aria-describedby="invitation-label-help invitation-label-errors"
                  aria-invalid={@form[:label].errors != []}
                />
                <p id="invitation-label-help" class="device-help">
                  A name you will recognize when building the app.
                </p>
                <div id="invitation-label-errors" class="device-field-errors" aria-live="polite">
                  <p :for={error <- @form[:label].errors}>{translate_error(error)}</p>
                </div>
              </div>
              <button type="submit" class="device-button device-button-primary">Create invitation</button>
            </.form>

            <p class="device-create-note">
              Links expire after 7 days. Collected identifiers are visible only to you.
              You can keep up to 25 invitations. Deleting one also removes its identifier.
            </p>
          </section>

          <section class="device-invitations" aria-labelledby="device-list-title">
            <div class="device-section-heading">
              <h2 id="device-list-title">Your invitations</h2>
              <span>{length(@invitations)}</span>
            </div>

            <div :if={@invitations == []} class="device-empty">
              <h3>No invitations yet</h3>
              <p>Create a link, send it to your friend, then return here for their device’s UDID.</p>
            </div>

            <div :if={@invitations != []} class="device-list">
              <article
                :for={invitation <- @invitations}
                class="device-row"
                id={"device-#{invitation.id}"}
              >
                <div class="device-row-heading">
                  <div>
                    <h3>{invitation.label}</h3>
                    <p class="device-row-status" data-status={Devices.invitation_status(invitation)}>
                      {status_label(Devices.invitation_status(invitation))}
                      <span :if={Devices.invitation_status(invitation) == :pending}>
                        · Expires {format_datetime(invitation.expires_at)}
                      </span>
                      <span :if={invitation.collected_at}>· {format_datetime(invitation.collected_at)}</span>
                    </p>
                  </div>
                  <.form
                    for={%{}}
                    action={"/users/devices/#{invitation.id}/delete"}
                    method="post"
                    id={"delete-device-#{invitation.id}"}
                  >
                    <button
                      type="submit"
                      class="device-button device-button-delete"
                      aria-label={"Delete #{invitation.label}"}
                      data-confirm="Delete this invitation and any collected device identifier?"
                    >Delete</button>
                  </.form>
                </div>

                <.copy_field
                  :if={Devices.invitation_status(invitation) == :pending}
                  id={"device-link-#{invitation.id}"}
                  label="Invitation link"
                  value={Map.get(@share_urls, invitation.id, "")}
                  copy_label={"Copy invitation link for #{invitation.label}"}
                  help="Copy this link to send it privately."
                />

                <.copy_field
                  :if={invitation.udid}
                  id={"device-udid-#{invitation.id}"}
                  label="UDID"
                  value={invitation.udid}
                  copy_label={"Copy UDID for #{invitation.label}"}
                  help="Copy this identifier when registering the device in your Apple developer account."
                />
              </article>
            </div>

            <p :if={@invitations != []} class="device-retention-note">
              Invitation records and collected identifiers are kept for 30 days after creation, then removed by hourly cleanup.
              Registering a device with Apple and sending an app build are separate steps.
            </p>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def invite(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="device-workspace device-invite-page" aria-labelledby="device-invite-title">
        <%= cond do %>
          <% @status in [:received, :collected] -> %>
            <header class="device-page-heading">
              <div>
                <h1 id="device-invite-title">Device identifier received</h1>
                <p>Your device’s UDID has been sent to the person who invited you.</p>
              </div>
            </header>
            <div class="device-completion">
              <h2>You can close this page</h2>
              <p>
                They can now register your device for a private build. They will send the app separately.
              </p>
              <p>
                If the Hrafnsyn collection profile remains in Settings → General → VPN &amp; Device Management, you can remove it.
              </p>
            </div>
          <% @status == :pending -> %>
            <header class="device-page-heading">
              <div>
                <h1 id="device-invite-title">Share your device identifier</h1>
                <p>
                  <strong>{@owner_name}</strong>
                  invited you to share the UDID for <strong>{@invitation.label}</strong>
                  so they can prepare a private Hrafnsyn build.
                </p>
              </div>
            </header>

            <div :if={@error} class="device-error" role="alert">
              <h2>Could not collect this device</h2>
              <p>{@error}</p>
            </div>

            <ol class="device-steps">
              <li>
                <h2>Open this page in Safari</h2>
                <p>
                  Use the iPhone or iPad you want to register. If you opened the link inside a messaging app, open it in Safari instead.
                </p>
              </li>
              <li>
                <h2>Download and approve the profile</h2>
                <p>
                  Tap the button below and allow the download. Then open Settings → General → VPN &amp; Device Management, choose the Hrafnsyn profile and tap Install.
                </p>
                <a
                  href={@profile_url}
                  class="device-button device-button-primary"
                  id="download-device-profile"
                >Download collection profile</a>
                <p class="device-help device-signing-note">
                  iOS may show “Not Signed” because this collection profile is unsigned.
                </p>
              </li>
              <li>
                <h2>Return here to finish</h2>
                <p>
                  After approval, iOS sends the identifier to this Hrafnsyn server. Return to Safari and check that it was received.
                </p>
                <a href="" class="device-button device-button-secondary">Check status</a>
              </li>
            </ol>

            <div class="device-privacy">
              <h2>What you are sharing</h2>
              <p>
                Only your device’s UDID is requested and shared with <strong>{@owner_name}</strong>.
                This profile does not install the app or enroll your device in remote management.
              </p>
              <p class="device-help">
                This invitation expires {format_datetime(@invitation.expires_at)}. No Hrafnsyn account is needed.
              </p>
            </div>
          <% true -> %>
            <header class="device-page-heading">
              <div>
                <h1 id="device-invite-title">This invitation is unavailable</h1>
                <p>It may have expired or been removed. Ask the person who sent it for a new link.</p>
              </div>
            </header>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :copy_label, :string, required: true
  attr :help, :string, required: true

  defp copy_field(assigns) do
    ~H"""
    <div class="device-field device-copy-field" data-device-copy-field>
      <label for={@id}>{@label}</label>
      <div class="device-copy-control">
        <input
          id={@id}
          type="text"
          readonly
          value={@value}
          spellcheck="false"
          autocomplete="off"
          aria-describedby={"#{@id}-help #{@id}-feedback"}
        />
        <button
          type="button"
          class="device-button device-button-secondary device-copy-button"
          data-device-copy
          data-copy-name={@label}
          aria-label={@copy_label}
          aria-controls={@id}
          aria-describedby={"#{@id}-feedback"}
        >
          <span class="device-copy-icon-copy" aria-hidden="true">
            <.icon name="hero-clipboard-document" class="device-copy-icon" />
          </span>
          <span class="device-copy-icon-check" aria-hidden="true">
            <.icon name="hero-check" class="device-copy-icon" />
          </span>
          <span data-device-copy-label>Copy</span>
        </button>
      </div>
      <p id={"#{@id}-help"} class="device-help">{@help}</p>
      <p
        id={"#{@id}-feedback"}
        class="device-help device-copy-feedback"
        role="status"
        aria-live="polite"
        aria-atomic="true"
        data-device-copy-feedback
      >
      </p>
    </div>
    """
  end

  defp status_label(:pending), do: "Awaiting device"
  defp status_label(:collected), do: "Received"
  defp status_label(:revoked), do: "Revoked"
  defp status_label(:expired), do: "Expired"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%d %b %Y, %H:%M UTC")

  defp format_datetime(_datetime), do: "—"

  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MiB"
end
