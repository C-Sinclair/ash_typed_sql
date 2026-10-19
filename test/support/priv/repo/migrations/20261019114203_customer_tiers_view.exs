defmodule AshTypedSql.Test.Repo.Migrations.CustomerTiersView20261019114203 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create materialized view "customer_tiers" as
    select c.id as customer_id, c.tier, count(o.id) as order_count
    from customers c
    left join orders o on o.customer_id = c.id
    group by c.id
    """)

    execute(~S"""
    create unique index "customer_tiers_primary_key_index" on "customer_tiers" ("customer_id")
    """)
  end

  def down do
    execute(~S"""
    drop materialized view "customer_tiers"
    """)
  end
end
