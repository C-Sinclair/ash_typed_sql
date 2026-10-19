[
  import_deps: [:ecto, :ecto_sql, :phoenix, :ash, :ash_postgres, :ash_phoenix, :ash_typescript],
  # ash_typed_sql exports no formatter config, so its DSL calls are listed here.
  locals_without_parens: [
    primary_key: 1,
    not_null: 1,
    materialized?: 1,
    argument_names: 1,
    as: 1,
    module_prefix: 1,
    function: 1,
    function: 2
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
