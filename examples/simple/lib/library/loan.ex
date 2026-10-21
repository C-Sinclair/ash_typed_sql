defmodule Library.Loan do
  @moduledoc "A book lent to a borrower, read and written through the queries under `priv/typed_sql/loans`."
  use Ash.Resource,
    domain: Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Table, AshTypedSql, AshTypedSql.Functions]

  # The `books` table has no resource of its own, so the generated `belongs_to :book` points at the view that reads it.
  typed_table "loans" do
    relationships? true
    references books: Library.Catalog
  end

  typed_sql do
    define_interface?(true)

    query :top_borrowers, "loans/top_borrowers.sql" do
      argument :limit, default: 10, constraints: [min: 1]
      not_null [:loan_count]
    end

    query :loans_for, "loans/loans_for.sql" do
      argument :borrower
      as :read
    end

    query :lend_book, "loans/lend_book.sql" do
      argument :book_id
      argument :borrower
      argument :due_on
      as :create
    end

    # An update or destroy binds the primary key from the record to $1, so `id` is not an argument.
    query :return_book, "loans/return_book.sql" do
      as :update
    end

    query :cancel_loan, "loans/cancel_loan.sql" do
      as :destroy
    end
  end

  typed_sql_functions do
    module_prefix Library.Expressions
    function :days_overdue, sql: "functions/days_overdue.sql"
  end

  postgres do
    repo Library.Repo
  end

  actions do
    defaults [:read]
  end

  code_interface do
    define :read
  end
end
