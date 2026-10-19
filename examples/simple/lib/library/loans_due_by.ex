defmodule Library.LoansDueBy do
  @moduledoc "Open loans due on or before a date, from the `loans_due_by` SQL function."
  use Ash.Resource,
    domain: Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View]

  typed_view "views/loans_due_by.sql" do
    primary_key [:loan_id]
    argument :as_of
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
