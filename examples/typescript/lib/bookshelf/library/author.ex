defmodule Bookshelf.Library.Author do
  use Ash.Resource,
    domain: Bookshelf.Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Table, AshTypescript.Resource]

  typed_table "authors", schema: "shelf"

  postgres do
    repo(Bookshelf.Repo)
  end

  actions do
    defaults [:read]
  end

  typescript do
    type_name "Author"
  end

  relationships do
    has_many :books, Bookshelf.Library.Book, public?: true

    has_one :stats, Bookshelf.Library.AuthorStats,
      destination_attribute: :author_id,
      public?: true
  end
end
