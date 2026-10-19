defmodule BookshelfWeb.RpcTest do
  use BookshelfWeb.ConnCase

  @le_guin "a0000000-0000-0000-0000-000000000001"
  @butler "a0000000-0000-0000-0000-000000000002"
  @earthsea "b0000000-0000-0000-0000-000000000001"
  @parable "b0000000-0000-0000-0000-000000000004"
  @ada "c0000000-0000-0000-0000-000000000001"

  setup %{conn: conn} do
    Bookshelf.Seeds.run!()
    {:ok, conn: put_private(conn, :plug_skip_csrf_protection, true)}
  end

  defp rpc(conn, action, payload) do
    conn
    |> post(~p"/rpc/run", Map.put(payload, "action", action))
    |> json_response(200)
  end

  defp rpc!(conn, action, payload) do
    assert %{"success" => true, "data" => data} = rpc(conn, action, payload)
    data
  end

  test "a view resource loads its relationship", %{conn: conn} do
    books =
      rpc!(conn, "list_books", %{
        "fields" => ["title", %{"author" => ["name"]}],
        "sort" => "title"
      })

    assert %{"title" => "A Wizard of Earthsea", "author" => %{"name" => "Ursula K. Le Guin"}} =
             hd(books)
  end

  test "a generic read query returns typed rows", %{conn: conn} do
    rows =
      rpc!(conn, "top_rated_books", %{
        "input" => %{"limit" => 2},
        "fields" => ["title", "averageRating", "reviewCount"]
      })

    assert [%{"title" => "A Wizard of Earthsea", "reviewCount" => 1}, %{"title" => "Kindred"}] =
             rows
  end

  test "an as :read query returns book records", %{conn: conn} do
    books =
      rpc!(conn, "books_by_author", %{"input" => %{"authorId" => @le_guin}, "fields" => ["title"]})

    assert Enum.map(books, & &1["title"]) == ["A Wizard of Earthsea", "The Dispossessed"]
  end

  test "as :create, :update and :destroy queries write through the books view", %{conn: conn} do
    created =
      rpc!(conn, "add_book", %{
        "input" => %{
          "authorId" => @butler,
          "title" => "Dawn",
          "publishedOn" => "1987-05-01",
          "copies" => 2
        },
        "fields" => ["id", "title", "copies"]
      })

    assert %{"title" => "Dawn", "copies" => 2, "id" => id} = created

    assert %{"title" => "Lilith's Brood"} =
             rpc!(conn, "retitle_book", %{
               "identity" => id,
               "input" => %{"title" => "Lilith's Brood"},
               "fields" => ["title"]
             })

    rpc!(conn, "withdraw_book", %{"identity" => id})

    titles =
      rpc!(conn, "books_by_author", %{"input" => %{"authorId" => @butler}, "fields" => ["title"]})

    assert Enum.map(titles, & &1["title"]) == ["Kindred", "Parable of the Sower"]
  end

  test "add_book binds a null publishedOn and defaults copies", %{conn: conn} do
    assert %{"publishedOn" => nil, "copies" => 1} =
             rpc!(conn, "add_book", %{
               "input" => %{"authorId" => @butler, "title" => "Fledgling", "publishedOn" => nil},
               "fields" => ["publishedOn", "copies"]
             })

    assert %{"success" => false} =
             rpc(conn, "add_book", %{
               "input" => %{"authorId" => @butler, "title" => "Wild Seed", "copies" => 0},
               "fields" => ["id"]
             })
  end

  test "generic write queries borrow and return a book", %{conn: conn} do
    [loan] =
      rpc!(conn, "borrow_book", %{
        "input" => %{"bookId" => @parable, "memberId" => @ada, "days" => 7},
        "fields" => ["id", "dueOn"]
      })

    assert loan["dueOn"] == Date.utc_today() |> Date.add(7) |> Date.to_iso8601()

    assert [%{"returnedOn" => returned_on}] =
             rpc!(conn, "return_loan", %{
               "input" => %{"id" => loan["id"]},
               "fields" => ["returnedOn"]
             })

    assert returned_on == Date.to_iso8601(Date.utc_today())
    assert [] = rpc!(conn, "return_loan", %{"input" => %{"id" => loan["id"]}, "fields" => ["id"]})
  end

  test "the days_overdue SQL function backs a calculation and a filter", %{conn: conn} do
    overdue =
      rpc!(conn, "list_loans", %{
        "fields" => ["overdueDays", %{"book" => ["title"]}],
        "filter" => %{"overdueDays" => %{"greaterThan" => 0}}
      })

    assert overdue == [%{"overdueDays" => 6, "book" => %{"title" => "Kindred"}}]
  end

  test "the materialized view changes only after :refresh", %{conn: conn} do
    stats_for = fn ->
      conn
      |> rpc!("list_author_stats", %{
        "fields" => ["loanCount"],
        "filter" => %{"authorId" => %{"eq" => @le_guin}}
      })
      |> hd()
    end

    assert %{"loanCount" => 1} = stats_for.()

    rpc!(conn, "borrow_book", %{
      "input" => %{"bookId" => @earthsea, "memberId" => @ada, "days" => 14},
      "fields" => ["id"]
    })

    assert %{"loanCount" => 1} = stats_for.()
    rpc!(conn, "refresh_author_stats", %{})
    assert %{"loanCount" => 2} = stats_for.()
  end

  test "the parameterized view takes its argument as read input", %{conn: conn} do
    since = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

    popular =
      rpc!(conn, "popular_books", %{
        "input" => %{"since" => since},
        "fields" => ["title", "loanCount"],
        "filter" => %{"loanCount" => %{"greaterThan" => 0}},
        "sort" => "-loanCount,title"
      })

    assert popular == [
             %{"title" => "Kindred", "loanCount" => 1},
             %{"title" => "Small Gods", "loanCount" => 1}
           ]
  end
end
