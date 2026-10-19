# Used by "mix format"
spark_locals_without_parens = [
  argument_names: 1,
  as: 1,
  description: 1,
  function: 1,
  function: 2,
  kind: 1,
  materialized?: 1,
  module_prefix: 1,
  not_null: 1,
  primary_key: 1,
  query: 2,
  query: 3,
  schema: 1,
  snapshot_dir: 1,
  sql: 1,
  sql_dir: 1,
  type_overrides: 1,
  typed_view: 1,
  typed_view: 2,
  volatile?: 1
]

[
  import_deps: [:ash, :ash_postgres, :spark],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
