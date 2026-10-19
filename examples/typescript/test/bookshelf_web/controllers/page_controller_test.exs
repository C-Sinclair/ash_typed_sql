defmodule BookshelfWeb.PageControllerTest do
  use BookshelfWeb.ConnCase

  test "GET / serves the TypeScript front end", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(id="app")
    assert html =~ "/assets/js/app.js"
  end
end
