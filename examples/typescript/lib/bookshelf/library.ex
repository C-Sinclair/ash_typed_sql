defmodule Bookshelf.Library do
  use Ash.Domain, otp_app: :bookshelf, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Bookshelf.Library.Author do
      rpc_action :list_authors, :read
    end

    resource Bookshelf.Library.Book do
      rpc_action :list_books, :read
      rpc_action :top_rated_books, :top_rated
      rpc_action :books_by_author, :by_author, enable_filter?: false, enable_sort?: false
      rpc_action :add_book, :add_book
      rpc_action :retitle_book, :retitle
      rpc_action :withdraw_book, :withdraw
    end

    resource Bookshelf.Library.Member do
      rpc_action :list_members, :read
    end

    resource Bookshelf.Library.Loan do
      rpc_action :list_loans, :read
      rpc_action :borrow_book, :borrow
      rpc_action :return_loan, :return_loan
    end

    resource Bookshelf.Library.AuthorStats do
      rpc_action :list_author_stats, :read
      rpc_action :refresh_author_stats, :refresh
    end

    resource Bookshelf.Library.PopularBook do
      rpc_action :popular_books, :read
    end
  end

  resources do
    resource(Bookshelf.Library.Author)
    resource(Bookshelf.Library.Book)
    resource(Bookshelf.Library.Member)
    resource(Bookshelf.Library.Loan)
    resource(Bookshelf.Library.AuthorStats)
    resource(Bookshelf.Library.PopularBook)
  end
end
