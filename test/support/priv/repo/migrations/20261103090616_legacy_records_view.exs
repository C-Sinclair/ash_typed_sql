defmodule AshTypedSql.Test.Repo.Migrations.LegacyRecordsView20261103090616 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "legacy_records" as
    select o.legacy_app_id, o.entity, o.legacy_id,
           jsonb_merge_agg(o.fields) over w as fields,
           o.observed_at as valid_from,
           lead(o.observed_at) over w as valid_to
    from entity_observations o
    window w as (partition by o.legacy_app_id, o.entity, o.legacy_id order by o.observed_at
                 rows between unbounded preceding and current row)
    """)
  end

  def down do
    execute(~S"""
    drop view "legacy_records"
    """)
  end
end
