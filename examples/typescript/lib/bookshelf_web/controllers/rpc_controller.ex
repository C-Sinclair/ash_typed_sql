defmodule BookshelfWeb.RpcController do
  use BookshelfWeb, :controller

  def run(conn, params) do
    json(conn, AshTypescript.Rpc.run_action(:bookshelf, conn, params))
  end

  def validate(conn, params) do
    json(conn, AshTypescript.Rpc.validate_action(:bookshelf, conn, params))
  end
end
