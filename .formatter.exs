# Used by "mix format"
spark_locals_without_parens = [
  allow_nil?: 1,
  argument: 1,
  argument: 2,
  argument: 3,
  as: 1,
  before_action?: 1,
  constraints: 1,
  default: 1,
  description: 1,
  function: 1,
  function: 2,
  get?: 1,
  kind: 1,
  materialized?: 1,
  message: 1,
  module_prefix: 1,
  not_null: 1,
  on: 1,
  only_when_valid?: 1,
  path: 1,
  prepare: 1,
  prepare: 2,
  primary_key: 1,
  public?: 1,
  query: 1,
  query: 2,
  query: 3,
  schema: 1,
  sensitive?: 1,
  snapshot_dir: 1,
  sql: 1,
  sql_dir: 1,
  type: 1,
  type_overrides: 1,
  typed_view: 1,
  typed_view: 2,
  validate: 1,
  validate: 2,
  volatile?: 1,
  where: 1
]

[
  import_deps: [:ash, :ash_postgres, :spark],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
