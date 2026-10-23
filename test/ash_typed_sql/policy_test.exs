defmodule AshTypedSql.PolicyTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.Test.{PolicyOrder, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{ada: insert_customer("Ada"), bob: insert_customer("Bob")}
  end

  defp insert_customer(name) do
    %{rows: [[id]]} = Repo.query!("insert into customers (name) values ($1) returning id", [name])
    Ecto.UUID.load!(id)
  end

  defp insert_order(customer_id, total) do
    %{rows: [[id]]} =
      Repo.query!("insert into orders (customer_id, total) values ($1, $2) returning id", [
        Ecto.UUID.dump!(customer_id),
        Decimal.new(total)
      ])

    id
  end

  defp read(action, customer_id, actor) do
    PolicyOrder
    |> Ash.Query.for_read(action, %{customer_id: customer_id}, actor: actor)
    |> Ash.read()
  end

  test "an authorize_if filter hides rows the actor does not own", %{ada: ada, bob: bob} do
    insert_order(ada, "1.00")

    assert {:ok, [_]} = read(:for_customer, ada, %{id: ada})
    assert {:ok, []} = read(:for_customer, ada, %{id: bob})
  end

  test "a forbid_if filter hides the rows it matches", %{ada: ada} do
    small = insert_order(ada, "1.00")
    insert_order(ada, "20.00")

    assert {:ok, [%{id: ^small}]} = read(:for_customer_forbid, ada, %{id: ada})
  end

  test "a forbid_if fragment filter that cannot run in Elixir hides every row", %{ada: ada} do
    insert_order(ada, "1.00")
    insert_order(ada, "20.00")

    assert {:ok, []} = read(:for_customer_forbid_fragment, ada, %{id: ada})
  end

  test "a simple check forbids or allows the whole read", %{ada: ada} do
    insert_order(ada, "1.00")

    assert {:ok, [_]} = read(:for_customer_admin, ada, %{admin?: true})
    assert {:error, %Ash.Error.Forbidden{}} = read(:for_customer_admin, ada, %{admin?: false})
  end
end
