defmodule BookshelfWeb.Router do
  use BookshelfWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {BookshelfWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :rpc do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  scope "/", BookshelfWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/rpc", BookshelfWeb do
    pipe_through :rpc

    post "/run", RpcController, :run
    post "/validate", RpcController, :validate
  end
end
