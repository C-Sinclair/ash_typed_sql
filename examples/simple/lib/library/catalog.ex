defmodule Library.Catalog do
  @moduledoc "Every book with its author's name, read from the `catalog` view."
  use Ash.Resource,
    domain: Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View, AshTypedSql]

  typed_view "views/catalog.sql" do
    primary_key [:id]
  end

  typed_sql do
    query :add_book, "catalog/add_book.sql" do
      argument_names [:author_name, :title, :published_on]
    end

    query :add_review, "catalog/add_review.sql" do
      argument_names [:book_id, :rating, :body]
    end
  end

  postgres do
    repo Library.Repo
  end

  relationships do
    has_one :stats, Library.BookStats, destination_attribute: :book_id
    has_many :loans, Library.Loan, destination_attribute: :book_id
  end
end
