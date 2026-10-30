defmodule AshTypedSql.Test.Repo.Migrations.OrganisationInvoicesView20261030114535 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "organisation_invoices" as
    select i.id, i.organisation_id, i.total
    from invoices i
    """)
  end

  def down do
    execute(~S"""
    drop view "organisation_invoices"
    """)
  end
end
