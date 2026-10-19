require Ash.Query

today = Date.utc_today()

section = fn title -> IO.puts("\n== #{title}") end

section.("View: Library.list_catalog/0 reads the catalog view, loading the stats relationship")

for book <- Library.list_catalog!(load: [:stats], query: Ash.Query.sort(Library.Catalog, :title)) do
  IO.puts(
    "#{book.title} (#{book.author_name}, #{book.published_on.year}): " <>
      "#{book.stats.review_count} reviews, average #{if avg = book.stats.average_rating, do: Decimal.round(avg, 2), else: "-"}"
  )
end

section.("View relationship filter: books with an open loan to grace")

Library.Catalog
|> Ash.Query.filter(exists(loans, borrower == "grace" and is_nil(returned_on)))
|> then(&Library.list_catalog!(query: &1))
|> Enum.map(& &1.title)
|> IO.inspect(label: "titles")

section.("Generic read query: Library.top_borrowers/1")

for row <- Library.top_borrowers!(2) do
  IO.puts("#{row.borrower}: #{row.loan_count} loans")
end

section.("Generic write query: Library.add_review/3 inserts into reviews")

[kindred] = Library.list_catalog!(query: Ash.Query.filter(Library.Catalog, title == "Kindred"))
[review] = Library.add_review!(kindred.id, 3, "Harrowing.")
IO.inspect(review, label: "returned row")

section.("Materialized view: book_stats is stale until Library.refresh_book_stats/0 runs")

stats_for = fn ->
  Library.list_book_stats!(query: Ash.Query.filter(Library.BookStats, book_id == ^kindred.id))
  |> hd()
  |> Map.take([:review_count, :average_rating])
end

IO.inspect(stats_for.(), label: "before refresh")
Library.refresh_book_stats!()
IO.inspect(stats_for.(), label: "after refresh ")

section.("as :read opt-in: Library.loans_for/1 returns Library.Loan records")

for loan <- Library.loans_for!("ada", load: [:book]) do
  IO.puts("##{loan.id} #{loan.book.title}, due #{loan.due_on}")
end

section.("as :create opt-in: Library.lend_book/3")

loan = Library.lend_book!(kindred.id, "margaret", Date.add(today, 14))
IO.inspect(Map.take(loan, [:id, :borrower, :loaned_on, :due_on, :returned_on]), label: "created")

section.("as :update opt-in: Library.return_book/1 binds $1 to the loan's id")

returned = Library.return_book!(loan)
IO.inspect(Map.take(returned, [:id, :returned_on]), label: "updated")

case Library.return_book(returned) do
  {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} ->
    IO.puts("returning it again is a stale record error, because the UPDATE matched no row")

  {:ok, _} ->
    IO.puts("returning it again unexpectedly succeeded")
end

section.("as :destroy opt-in: Library.cancel_loan/1")

:ok = Library.cancel_loan!(returned)
IO.puts("loan ##{returned.id} deleted, #{length(Library.list_loans!())} loans remain")

section.("Parameterized view: Library.loans_due_by/1 calls the loans_due_by SQL function")

for row <-
      Library.loans_due_by!(today,
        load: [:book],
        query: Ash.Query.sort(Library.LoansDueBy, :due_on)
      ) do
  IO.puts("#{row.borrower} owes #{row.book.title}, due #{row.due_on}")
end

section.("SQL function: days_overdue(due_on, ^today) in a filter")

Library.Loan
|> Ash.Query.filter(days_overdue(due_on, ^today) > 5)
|> Ash.Query.sort(:due_on)
|> then(&Library.list_loans!(query: &1, load: [:book]))
|> Enum.each(fn loan ->
  IO.puts("#{loan.borrower}: #{loan.book.title} is #{Date.diff(today, loan.due_on)} days overdue")
end)
