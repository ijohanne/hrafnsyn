defmodule HrafnsynWeb.PageController do
  use HrafnsynWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
