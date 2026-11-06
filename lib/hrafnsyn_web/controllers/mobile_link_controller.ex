defmodule HrafnsynWeb.MobileLinkController do
  use HrafnsynWeb, :controller

  def association(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> json(Hrafnsyn.MobileLinks.association())
  end
end
