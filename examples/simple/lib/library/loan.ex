defmodule Library.Loan do
  @moduledoc "A book lent to a borrower, read and written through the queries under `priv/typed_sql/loans`."
  use Ash.Resource,
    domain: Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View, AshTypedSql, AshTypedSql.Functions]

  # The CRUD opt-ins check their columns against the resource's attributes, so a typed_view over the table generates them. See docs/friction/FF-191026-crud-opt-in-needs-declared-attributes.md.
  typed_view "tables/loans.sql" do
    primary_key [:id]
  end

  typed_sql do
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
