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
      argument_names [:limit]
      not_null [:review_count]
    end

    query :by_author, "books/by_author.sql" do
      argument_names [:author_id]
      as :read
    end

    query :add_book, "books/add_book.sql" do
      argument_names [:author_id, :title, :published_on, :copies]
      as :create
    end

    query :retitle, "books/retitle.sql" do
      argument_names [:id, :title]
      as :update
    end

    query :withdraw, "books/withdraw.sql" do
      argument_names [:id]
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
