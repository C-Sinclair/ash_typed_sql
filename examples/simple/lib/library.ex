defmodule Library do
  @moduledoc "A bookshelf whose resources are generated from the SQL under `priv/typed_sql`."
  use Ash.Domain

  resources do
    resource Library.Catalog do
      define :list_catalog, action: :read
      define :get_book, action: :read, get_by: [:id]
      define :add_book, args: [:author_name, :title, :published_on]
      define :add_review, args: [:book_id, :rating, :body]
    end

    resource Library.BookStats do
      define :list_book_stats, action: :read
      define :refresh_book_stats, action: :refresh
    end

    resource Library.LoansDueBy do
      define :loans_due_by, action: :read, args: [:as_of]
    end

    resource Library.Loan do
      define :list_loans, action: :read
      define :loans_for, args: [:borrower]
      define :lend_book, args: [:book_id, :borrower, :due_on]
      define :return_book
      define :cancel_loan
      define :top_borrowers, args: [:limit]
    end
  end
end
