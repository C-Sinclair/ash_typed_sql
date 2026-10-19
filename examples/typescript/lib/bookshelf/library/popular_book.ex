defmodule Bookshelf.Library.PopularBook do
  use Ash.Resource,
    domain: Bookshelf.Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View, AshTypescript.Resource]

  typed_view "views/popular_books.sql" do
    primary_key [:book_id]
    not_null [:loan_count]
    argument :since
  end

  postgres do
    repo(Bookshelf.Repo)
  end

  typescript do
    type_name "PopularBook"
  end

  relationships do
    belongs_to :book, Bookshelf.Library.Book do
      source_attribute :book_id
      define_attribute? false
      public? true
    end
  end
end
