defmodule LibraryTest do
  use ExUnit.Case, async: true

  require Ash.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Library.Repo)
    [%{id: book_id}] = Library.add_book!("Octavia E. Butler", "Kindred", ~D[1979-06-01])
    %{book_id: book_id, today: Date.utc_today()}
  end

  test "the catalog view reads books with their author's name", %{book_id: book_id} do
    assert %Library.Catalog{title: "Kindred", author_name: "Octavia E. Butler"} =
             Library.get_book!(book_id)
  end

  test "add_review is a generic action returning typed rows", %{book_id: book_id} do
    assert [%Library.Catalog.AddReviewRow{book_id: ^book_id, rating: 4}] =
             Library.add_review!(book_id, 4, "Good.")
  end

  test "add_review takes a nil body, which binds SQL NULL", %{book_id: book_id} do
    assert [%Library.Catalog.AddReviewRow{}] = Library.add_review!(book_id, 4, nil)

    assert %{rows: [[nil]]} =
             Library.Repo.query!("select body from reviews where book_id = $1", [
               Ecto.UUID.dump!(book_id)
             ])
  end

  test "add_review refuses a rating outside its constraints", %{book_id: book_id} do
    assert {:error, %Ash.Error.Invalid{}} = Library.add_review(book_id, 6, "Too good.")
  end

  test "book_stats changes only after refresh", %{book_id: book_id} do
    Library.add_review!(book_id, 4, "Good.")
    assert Library.get_book!(book_id, load: [:stats]).stats == nil

    Library.refresh_book_stats!()

    assert %{review_count: 1} = Library.get_book!(book_id, load: [:stats]).stats
  end

  test "lend, read, return and cancel a loan through the CRUD opt-ins", %{
    book_id: book_id,
    today: today
  } do
    loan = Library.lend_book!(book_id, "ada", Date.add(today, 7))
    assert %Library.Loan{borrower: "ada", returned_on: nil} = loan
    assert [%Library.Loan{id: id}] = Library.loans_for!("ada")
    assert id == loan.id

    assert %{returned_on: ^today} = returned = Library.return_book!(loan)
    assert {:error, %Ash.Error.Invalid{}} = Library.return_book(returned)

    assert :ok = Library.cancel_loan!(returned)
    assert Library.list_loans!() == []
  end

  test "top_borrowers counts loans per borrower", %{book_id: book_id, today: today} do
    for borrower <- ["ada", "ada", "grace"], do: Library.lend_book!(book_id, borrower, today)

    assert [%{borrower: "ada", loan_count: 2}] = Library.top_borrowers!(1)
  end

  test "loans_due_by takes its date as a read argument", %{book_id: book_id, today: today} do
    Library.lend_book!(book_id, "ada", Date.add(today, -1))
    Library.lend_book!(book_id, "grace", Date.add(today, 30))

    assert [%Library.LoansDueBy{borrower: "ada"}] = Library.loans_due_by!(today)
  end

  test "days_overdue runs in Postgres inside a filter", %{book_id: book_id, today: today} do
    Library.lend_book!(book_id, "ada", Date.add(today, -10))
    Library.lend_book!(book_id, "grace", Date.add(today, -2))

    query = Ash.Query.filter(Library.Loan, days_overdue(due_on, ^today) > 5)
    assert [%{borrower: "ada"}] = Library.list_loans!(query: query)
  end
end
