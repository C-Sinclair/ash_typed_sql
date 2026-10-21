defmodule AshTypedSql.Sigil do
  @moduledoc "The `~SQL` sigil for inline `query` statements, imported inside `typed_sql`."

  @doc "Returns the statement unchanged. It marks the string as SQL for editors and readers."
  def sigil_SQL(sql, []), do: sql
end
