defmodule HrafnsynWeb.UserRegistrationControllerTest do
  use HrafnsynWeb.ConnCase, async: true

  describe "public registration" do
    test "GET /users/register is not exposed", %{conn: conn} do
      conn = get(conn, "/users/register")
      assert response(conn, 404) == "Not Found"
    end

    test "POST /users/register is not exposed", %{conn: conn} do
      conn =
        post(conn, "/users/register", %{
          "user" => %{"email" => "nope@example.com"}
        })

      assert response(conn, 404) == "Not Found"
    end
  end
end
