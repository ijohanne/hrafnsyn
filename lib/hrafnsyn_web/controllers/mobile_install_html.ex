defmodule HrafnsynWeb.MobileInstallHTML do
  use HrafnsynWeb, :html

  def index(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="device-workspace device-invite-page" aria-labelledby="install-page-title">
        <header class="device-page-heading">
          <h1 id="install-page-title">Install the app</h1>
          <p>
            <strong>{@mobile_build.title}</strong> · Build {@mobile_build.bundle_version}
          </p>
          <p>Use Safari on the iPhone or iPad you registered. You won’t need a computer or cable.</p>
        </header>

        <ol class="device-steps">
          <li>
            <h2>Start the installation</h2>
            <p>Tap below, then choose Install in the system prompt.</p>
            <a
              href={@install_url}
              id="install-ios-app"
              class="device-button device-button-primary"
              rel="noreferrer nofollow"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Install on this device
            </a>
            <p class="device-help device-signing-note">
              This link expires after {@expires_in_minutes} minutes.
              <a href={~p"/users/devices/install"}>Refresh the install link</a>
              if needed.
            </p>
          </li>
          <li>
            <h2>Find the app on your Home Screen</h2>
            <p>
              The download continues outside Safari. Return to your Home Screen and wait for
              the app icon to finish loading, then open it.
            </p>
          </li>
          <li>
            <h2>Follow any device prompts</h2>
            <p>
              If asked, turn on Developer Mode in Settings → Privacy &amp; Security,
              restart your device, and confirm. Then open the app again.
            </p>
          </li>
        </ol>

        <div class="device-privacy">
          <h2>If installation doesn’t finish</h2>
          <p>
            Your device must be included in this signed build. If you registered after it was
            published, ask the administrator for a new build. Keep an internet connection during
            installation.
          </p>
          <p>
            On a Mac, <a href={~p"/users/devices/app.ipa"}>download the IPA</a>
            and install it with Xcode or Apple Configurator.
          </p>
          <p><a href={~p"/users/devices"}>Back to device invitations</a></p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
