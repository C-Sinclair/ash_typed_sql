defmodule AshTypedSql.Test.Repo.Migrations.LargeInvoicesView20261030114536 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create materialized view "large_invoices" as
    select i.id, i.organisation_id, i.total
    from invoices i
    where i.total >= 100
    """)

    execute(~S"""
    create unique index "large_invoices_primary_key_index" on "large_invoices" ("id")
    """)

    execute(~S"""
    create index "large_invoices_tenant_index" on "large_invoices" ("organisation_id")
    """)
  end

  def down do
    execute(~S"""
    drop materialized view "large_invoices"
    """)
  end
end
