defmodule AshTypedSql.Test.Repo.Migrations.CustomerStatsSinceView20261019114806 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create function "customer_stats_since"("since" timestamp with time zone)
    returns table ("customer_id" uuid, "name" text, "order_count" bigint)
    language sql stable
    as $typed_sql$
    select c.id as customer_id, c.name, count(o.id) as order_count
    from customers c
    left join orders o on o.customer_id = c.id and o.inserted_at >= $1
    group by c.id
    $typed_sql$
    """)
  end

  def down do
    execute(~S"""
    drop function "customer_stats_since"(timestamp with time zone)
    """)
  end
end
