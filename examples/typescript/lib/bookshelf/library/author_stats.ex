defmodule Bookshelf.Library.AuthorStats do
  use Ash.Resource,
    domain: Bookshelf.Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View, AshTypescript.Resource]

  typed_view "views/author_stats.sql" do
    primary_key [:author_id]
    not_null [:book_count, :loan_count]
    materialized? true
  end

  postgres do
    repo(Bookshelf.Repo)
  end

  typescript do
    type_name "AuthorStats"
  end

  relationships do
    belongs_to :author, Bookshelf.Library.Author do
      source_attribute :author_id
      define_attribute? false
      public? true
    end
  end
end
