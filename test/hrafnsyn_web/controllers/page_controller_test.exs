defmodule HrafnsynWeb.PageControllerTest do
  use HrafnsynWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Air and sea traffic on one living map."
    assert response =~ "Live Contacts"
  end
end
