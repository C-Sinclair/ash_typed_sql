defmodule Library.BookStats do
  @moduledoc "Review counts and average rating per book, from the `book_stats` materialized view."
  use Ash.Resource,
    domain: Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View]

  typed_view "views/book_stats.sql" do
    primary_key([:book_id])
    not_null([:review_count])
    materialized?(true)
  end

  postgres do
    repo Library.Repo
  end

  relationships do
    belongs_to :book, Library.Catalog do
      source_attribute :book_id
      define_attribute? false
    end
  end
end
