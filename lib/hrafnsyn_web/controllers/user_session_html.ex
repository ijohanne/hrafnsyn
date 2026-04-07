defmodule HrafnsynWeb.UserSessionHTML do
  use HrafnsynWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:hrafnsyn, Hrafnsyn.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
