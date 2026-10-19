defmodule AshTypedSql.Test.Repo.Migrations.CustomerStatsView20261019114202 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "customer_stats" as
    select c.id as customer_id, c.name, c.email, count(o.id) as order_count, sum(o.total) as lifetime_value
    from customers c
    left join orders o on o.customer_id = c.id
    group by c.id
    """)
  end

  def down do
    execute(~S"""
    drop view "customer_stats"
    """)
  end
end
