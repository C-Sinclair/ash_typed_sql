defmodule Bookshelf.Library.Member do
  use Ash.Resource,
    domain: Bookshelf.Library,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View, AshTypescript.Resource]

  typed_view "views/members.sql" do
    primary_key [:id]
  end

  postgres do
    repo(Bookshelf.Repo)
  end

  typescript do
    type_name "Member"
  end

  relationships do
    has_many :loans, Bookshelf.Library.Loan, public?: true
  end
end
