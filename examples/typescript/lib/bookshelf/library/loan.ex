defmodule Bookshelf.Library.Loan do
  use Ash.Resource,
    domain: Bookshelf.Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Table, AshTypedSql, AshTypedSql.Functions, AshTypescript.Resource]

  typed_table "loans" do
    schema "shelf"
    relationships? true
    references books: Bookshelf.Library.Book, members: Bookshelf.Library.Member
  end

  typed_sql do
    query :borrow, "loans/borrow.sql" do
      argument :book_id
      argument :member_id
      argument :days, constraints: [min: 1]
    end

    query :return_loan, "loans/return_loan.sql" do
      argument :id
    end
  end

  typed_sql_functions do
    module_prefix Bookshelf.Expressions
    function :days_overdue, sql: "functions/days_overdue.sql"
  end

  postgres do
    repo(Bookshelf.Repo)
  end

  actions do
    defaults [:read]
  end

  typescript do
    type_name "Loan"
  end

  calculations do
    calculate :overdue_days, :integer, expr(days_overdue(due_on, returned_on)), public?: true
  end
end
