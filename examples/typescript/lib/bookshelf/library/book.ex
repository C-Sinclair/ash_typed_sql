defmodule Bookshelf.Library.Book do
  use Ash.Resource,
    domain: Bookshelf.Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View, AshTypedSql, AshTypescript.Resource]

  typed_view "views/books.sql" do
    primary_key [:id]
  end

  typed_sql do
    query :top_rated, "books/top_rated.sql" do
      argument :limit, default: 5, constraints: [min: 1, max: 50]
      not_null [:review_count]
    end

    query :by_author, "books/by_author.sql" do
      argument :author_id
      as :read
    end

    query :add_book, "books/add_book.sql" do
      argument :author_id
      argument :title
      argument :published_on, allow_nil?: true
      argument :copies, default: 1, constraints: [min: 1]
      as :create
    end

    # An update or destroy binds the primary key from the record to $1, so `id` is not an argument.
    query :retitle, "books/retitle.sql" do
      argument :title
      as :update
    end

    query :withdraw, "books/withdraw.sql" do
      as :destroy
    end
  end

  postgres do
    repo(Bookshelf.Repo)
  end

  typescript do
    type_name "Book"
  end

  relationships do
    belongs_to :author, Bookshelf.Library.Author do
      source_attribute :author_id
      define_attribute? false
      public? true
    end

    has_many :loans, Bookshelf.Library.Loan, public?: true
  end
end
