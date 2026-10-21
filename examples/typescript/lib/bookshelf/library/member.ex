defmodule Bookshelf.Library.Member do
  use Ash.Resource,
    domain: Bookshelf.Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Table, AshTypescript.Resource]

  typed_table "members", schema: "shelf"

  postgres do
    repo(Bookshelf.Repo)
  end

  actions do
    defaults [:read]
  end

  typescript do
    type_name "Member"
  end

  relationships do
    has_many :loans, Bookshelf.Library.Loan, public?: true
  end
end
