defmodule BookshelfWeb.PageController do
  use BookshelfWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
