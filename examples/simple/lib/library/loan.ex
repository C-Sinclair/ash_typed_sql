defmodule Library.Loan do
  @moduledoc "A book lent to a borrower, read and written through the queries under `priv/typed_sql/loans`."
  use Ash.Resource,
    domain: Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View, AshTypedSql, AshTypedSql.Functions]

  # The CRUD opt-ins check their columns against the resource's attributes, so a typed_view over the table generates them. See docs/friction/FF-191026-crud-opt-in-needs-declared-attributes.md.
  typed_view "tables/loans.sql" do
    primary_key([:id])
  end

  typed_sql do
    query :top_borrowers, "loans/top_borrowers.sql" do
      argument_names([:limit])
      not_null([:loan_count])
    end

    query :loans_for, "loans/loans_for.sql" do
      argument_names([:borrower])
      as(:read)
    end

    query :lend_book, "loans/lend_book.sql" do
      argument_names([:book_id, :borrower, :due_on])
      as(:create)
    end

    query :return_book, "loans/return_book.sql" do
      argument_names([:id])
      as(:update)
    end

    query :cancel_loan, "loans/cancel_loan.sql" do
      argument_names([:id])
      as(:destroy)
    end
  end

  typed_sql_functions do
    module_prefix(Library.Expressions)
    function(:days_overdue, sql: "functions/days_overdue.sql")
  end

  postgres do
    table "loans"
    repo Library.Repo
  end

  relationships do
    belongs_to :book, Library.Catalog do
      source_attribute :book_id
      define_attribute? false
    end
  end
end
