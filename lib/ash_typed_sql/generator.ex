if Code.ensure_loaded?(Igniter) do
  defmodule AshTypedSql.Generator do
    @moduledoc """
    Source edits and codegen calls shared by the `mix ash_typed_sql.gen.*` tasks.

    Each generator describes its SQL against the resource's repo with the same functions `mix ash.codegen` calls, writes the snapshot, and then writes the source that the snapshot types.
    """

    alias AshTypedSql.Codegen.Query, as: QueryCodegen
    alias AshTypedSql.TypeMap

    @doc "Parses a module name given on the command line, and raises unless it is a compiled module."
    @spec compiled_module!(String.t()) :: module()
    def compiled_module!(name) do
      module = Igniter.Project.Module.parse(name)

      unless Code.ensure_loaded?(module) do
        Mix.raise("#{inspect(module)} is not a compiled module")
      end

      module
    end

    @doc "Returns the `sql_dir` of a resource, or the default when it has no `typed_sql` section."
    @spec sql_dir(module()) :: String.t()
    def sql_dir(resource),
      do: Spark.Dsl.Extension.get_opt(resource, [:typed_sql], :sql_dir, "priv/typed_sql")

    @doc "Returns `path`, absolute or relative to the working directory, relative to `sql_dir`."
    @spec relative_sql_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
    def relative_sql_path(path, sql_dir) do
      absolute = Path.expand(path)
      dir = Path.expand(sql_dir)

      cond do
        not File.regular?(absolute) ->
          {:error, "#{path} does not exist"}

        String.starts_with?(absolute, dir <> "/") ->
          {:ok, Path.relative_to(absolute, dir)}

        true ->
          {:error,
           "#{path} is outside the resource's sql_dir #{sql_dir}. Move the file under #{sql_dir}, or set `sql_dir` in the resource's `typed_sql` section"}
      end
    end

    @doc "Describes `query` against the resource's repo database, with the same function `mix ash.codegen` calls, without counting its arguments."
    @spec describe_query(module(), AshTypedSql.Query.t()) :: map()
    def describe_query(resource, query) do
      {:ok, _} = Application.ensure_all_started(:postgrex)
      repo = AshPostgres.DataLayer.Info.repo(resource, :mutate)

      QueryCodegen.with_connections(
        repo.config(),
        &QueryCodegen.snapshot(&1, &2, resource, query, check_arguments?: false)
      )
    end

    @doc "Writes a snapshot file into the igniter."
    @spec put_snapshot(Igniter.t(), String.t(), map()) :: Igniter.t()
    def put_snapshot(igniter, path, snapshot) do
      contents = QueryCodegen.encode(snapshot)

      Igniter.create_or_update_file(
        igniter,
        path,
        contents,
        &Rewrite.Source.update(&1, :content, contents)
      )
    end

    @doc "Adds `extension` to the resource's `use Ash.Resource` unless it is listed already."
    @spec add_extension(Igniter.t(), module(), module()) :: Igniter.t()
    def add_extension(igniter, resource, extension),
      do: Spark.Igniter.add_extension(igniter, resource, Ash.Resource, :extensions, extension)

    @doc "Returns one `argument` line per snapshot parameter, named from `names` and then `arg<n>`."
    @spec argument_lines(map(), [String.t()]) :: [String.t()]
    def argument_lines(snapshot, names) do
      snapshot["params"]
      |> Enum.with_index(1)
      |> Enum.map(fn {param, position} ->
        name = Enum.at(names, position - 1) || "arg#{position}"
        "argument #{inspect(String.to_atom(name))}, #{type_code(param)}"
      end)
    end

    @doc "Returns the `typed_struct` block with one field per snapshot column."
    @spec typed_struct(map(), AshTypedSql.Query.t()) :: String.t()
    def typed_struct(snapshot, query) do
      fields =
        Enum.map_join(snapshot["columns"], "\n", fn column ->
          not_null = if AshTypedSql.Returns.not_null?(query, column), do: ", allow_nil?: false"

          "field #{inspect(String.to_atom(column["name"]))}, #{type_code(column["type"], query.type_overrides)}#{not_null}"
        end)

      "typed_struct do\n#{fields}\nend"
    end

    @doc "Creates the `returns` module from the snapshot, or rewrites the `typed_struct` block of an existing one."
    @spec write_returns(Igniter.t(), module(), map(), AshTypedSql.Query.t()) :: Igniter.t()
    def write_returns(igniter, module, snapshot, query) do
      block = typed_struct(snapshot, query)

      case Igniter.Project.Module.module_exists(igniter, module) do
        {true, igniter} ->
          Igniter.Project.Module.find_and_update_module!(igniter, module, fn zipper ->
            case Igniter.Code.Function.move_to_function_call_in_current_scope(
                   zipper,
                   :typed_struct,
                   1
                 ) do
              {:ok, zipper} ->
                {:ok, Igniter.Code.Common.replace_code(zipper, block)}

              :error ->
                {:error, "#{inspect(module)} has no `typed_struct` block to rewrite"}
            end
          end)

        {false, igniter} ->
          Igniter.Project.Module.create_module(igniter, module, """
          @moduledoc "A row returned by the `#{query.name}` query."
          use Ash.TypedStruct

          #{block}
          """)
      end
    end

    # Enums are written as atoms rather than the enum module the resource generates, because the resource compiles after its `returns` module and that module cannot name it.
    @doc false
    def type_code(description, overrides \\ [])

    def type_code(%{"type" => "array", "of" => of}, overrides) do
      case type_parts(of, overrides) do
        {type, nil} -> "{:array, #{type}}"
        {type, constraints} -> "{:array, #{type}}, constraints: [items: #{constraints}]"
      end
    end

    def type_code(description, overrides) do
      case type_parts(description, overrides) do
        {type, nil} -> type
        {type, constraints} -> "#{type}, constraints: #{constraints}"
      end
    end

    defp type_parts(%{"type" => "enum", "values" => values}, _overrides),
      do: {":atom", "[one_of: #{inspect(Enum.map(values, &String.to_atom/1))}]"}

    defp type_parts(%{"type" => "override", "name" => name}, overrides),
      do: {inspect(Keyword.fetch!(overrides, String.to_atom(name))), nil}

    defp type_parts(description, _overrides),
      do: {inspect(TypeMap.to_ash(description, fn _ -> nil end)), nil}
  end
end
