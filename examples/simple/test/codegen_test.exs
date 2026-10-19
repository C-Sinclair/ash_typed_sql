defmodule Library.CodegenTest do
  use ExUnit.Case, async: false

  test "committed snapshots match what Postgres describes for the migrated schema" do
    Mix.Task.rerun("ash.codegen", ["--check"])
  end
end
