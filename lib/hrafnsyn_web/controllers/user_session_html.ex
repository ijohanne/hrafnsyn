defmodule HrafnsynWeb.UserSessionHTML do
  use HrafnsynWeb, :html

  embed_templates "user_session_html/*"

  def native_return_link(conn) do
    conn
    |> Plug.Conn.get_session(:user_return_to)
    |> Hrafnsyn.MobileLinks.open_return_path()
  end
end
