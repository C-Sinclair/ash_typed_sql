defmodule AshTypedSql.Functions.Info do
  @moduledoc "Introspection for the `typed_sql_functions` section and the modules it generates."

  use Spark.InfoGenerator, extension: AshTypedSql.Functions, sections: [:typed_sql_functions]

  @doc "Returns the snapshot path for a function."
  @spec snapshot_path(Ash.Resource.t() | map(), AshTypedSql.Function.t()) :: String.t()
  def snapshot_path(resource, function) do
    resource
    |> Spark.Dsl.Extension.get_opt(
      [:typed_sql_functions],
      :snapshot_dir,
      "priv/typed_sql/snapshots"
    )
    |> Path.join("functions/#{function.schema}.#{function.name}.json")
  end

  @doc "Returns the path of a function's `sql` file, relative to the project root."
  @spec sql_path(Ash.Resource.t() | map(), AshTypedSql.Function.t()) :: String.t()
  def sql_path(resource, function) do
    resource
    |> Spark.Dsl.Extension.get_opt([:typed_sql_functions], :sql_dir, "priv/typed_sql")
    |> Path.join(function.sql)
  end

  @doc "Returns the module generated for a function."
  @spec expression_module(Ash.Resource.t() | map(), AshTypedSql.Function.t()) :: module()
  def expression_module(resource, function) do
    prefix =
      Spark.Dsl.Extension.get_opt(resource, [:typed_sql_functions], :module_prefix) ||
        Spark.Dsl.Extension.get_persisted(resource, :module)

    Module.concat(prefix, Macro.camelize(to_string(function.name)))
  end

  @doc "Returns every generated module of `resources`, for `config :ash, :custom_expressions`."
  @spec expression_modules([Ash.Resource.t()]) :: [module()]
  def expression_modules(resources) do
    for resource <- resources,
        AshTypedSql.Functions in Spark.extensions(resource),
        function <- typed_sql_functions(resource),
        do: expression_module(resource, function)
  end
end
