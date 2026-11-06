defmodule HrafnsynWeb.Router do
  use HrafnsynWeb, :router

  import HrafnsynWeb.UserAuth

  @browser_headers %{
    "content-security-policy" =>
      "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; " <>
        "script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
        "font-src 'self' data: https://fonts.gstatic.com; img-src 'self' data: blob: https:; " <>
        "connect-src 'self' https: ws: wss:; worker-src 'self' blob:; form-action 'self'"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HrafnsynWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mobile_upload do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :fetch_current_scope_for_user
    plug :require_authenticated_user
    plug :require_admin_user
    plug HrafnsynWeb.Plugs.MobileUpload
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @browser_headers
  end

  pipeline :mobile_release_api do
    plug HrafnsynWeb.Plugs.MobileReleaseAuth
  end

  pipeline :mobile_release_upload do
    plug HrafnsynWeb.Plugs.MobileUpload
  end

  scope "/api/mobile-release", HrafnsynWeb do
    pipe_through :api
    post "/session", MobileReleaseController, :refresh, log: false
  end

  scope "/api/mobile-release", HrafnsynWeb do
    pipe_through [:api, :mobile_release_api]
    get "/devices", MobileReleaseController, :devices, log: false
  end

  scope "/api/mobile-release", HrafnsynWeb do
    pipe_through [:api, :mobile_release_api, :mobile_release_upload]
    post "/ipa", MobileReleaseController, :publish, log: false
  end

  scope "/", HrafnsynWeb do
    pipe_through :mobile_upload
    post "/admin/mobile-build", MobileBuildController, :create
  end

  pipeline :dashboard_access do
    plug :require_authenticated_user_unless_public
  end

  live_session :dashboard,
    on_mount: [
      {HrafnsynWeb.LiveAuth, :mount_current_scope},
      {HrafnsynWeb.LiveAuth, :ensure_authenticated_user_unless_public}
    ] do
    scope "/", HrafnsynWeb do
      pipe_through [:browser, :dashboard_access]

      live "/", DashboardLive, :index
    end
  end

  live_session :admin,
    on_mount: [
      {HrafnsynWeb.LiveAuth, :mount_current_scope},
      {HrafnsynWeb.LiveAuth, :ensure_admin}
    ] do
    scope "/admin", HrafnsynWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/users", Admin.UsersLive, :index
    end
  end

  live_session :account,
    on_mount: [
      {HrafnsynWeb.LiveAuth, :mount_current_scope},
      {HrafnsynWeb.LiveAuth, :ensure_authenticated_user}
    ] do
    scope "/", HrafnsynWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/users/tokens", UserTokensLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", HrafnsynWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hrafnsyn, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HrafnsynWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", HrafnsynWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/devices", DeviceController, :index
    get "/users/devices/app.ipa", MobileBuildController, :download
    post "/users/devices", DeviceController, :create
    post "/users/devices/:id/delete", DeviceController, :delete

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", HrafnsynWeb do
    pipe_through [:browser]

    get "/devices/invite/:token", DeviceController, :invite, log: false
    get "/devices/invite/:token/profile", DeviceController, :profile, log: false

    get "/grpc", PageController, :grpc
    get "/grpc/tracking.proto", PageController, :grpc_proto
    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Apple posts a signed CMS body outside the browser session. A separate challenge
  # authorizes only this bounded, single-device collection callback.
  scope "/", HrafnsynWeb do
    post "/devices/invite/:token/callback", DeviceController, :callback, log: false
  end
end
