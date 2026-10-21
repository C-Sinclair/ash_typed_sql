defmodule Library do
  @moduledoc "A bookshelf whose resources are generated from the SQL under `priv/typed_sql`."
  use Ash.Domain

  resources do
    resource Library.Catalog do
      define :get_book, action: :read, get_by: [:id]
    end

    resource Library.BookStats
    resource Library.LoansDueBy
    resource Library.Loan
  end
end
