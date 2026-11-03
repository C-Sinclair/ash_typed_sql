defmodule AshTypedSql.AsOfTest do
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshTypedSql.Test.Repo
  alias AshTypedSql.Test.Views.{LegacyApp, LegacyRecords}

  @first ~U[2026-01-01 00:00:00.000000Z]
  @second ~U[2026-02-01 00:00:00.000000Z]
  @third ~U[2026-03-01 00:00:00.000000Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    %{rows: [[app_id]]} =
      Repo.query!("insert into legacy_apps (name) values ('crm') returning id")

    %{app_id: app_id}
  end

  defp observe(app_id, legacy_id, fields, observed_at) do
    Repo.query!(
      """
      insert into entity_observations (legacy_app_id, entity, legacy_id, fields, observed_at)
      values ($1, 'customer', $2, $3, $4)
      """,
      [app_id, legacy_id, fields, observed_at]
    )
  end

  defp current(opts \\ []) do
    LegacyRecords
    |> Ash.Query.for_read(:current)
    |> Ash.Query.sort(:legacy_id)
    |> Ash.read!(opts)
  end

  describe "a typed_view whose read filters on now()" do
    setup %{app_id: app_id} do
      observe(app_id, "c1", %{"name" => "Ada"}, @first)
      observe(app_id, "c1", %{"email" => "ada@example.com"}, @second)
      observe(app_id, "c1", %{"name" => "Ada Lovelace"}, @third)
      :ok
    end

    test "without as_of returns each record as it stands now" do
      assert [%{legacy_id: "c1", fields: fields, valid_from: @third, valid_to: nil}] = current()
      assert fields == %{"name" => "Ada Lovelace", "email" => "ada@example.com"}
    end

    test "Ash.Query.as_of/2 returns each record as it stood at that instant" do
      assert [%{fields: %{"name" => "Ada"} = fields}] =
               LegacyRecords
               |> Ash.Query.for_read(:current)
               |> Ash.Query.as_of(~U[2026-01-15 00:00:00Z])
               |> Ash.read!()

      refute Map.has_key?(fields, "email")
    end

    test "the as_of read option behaves like Ash.Query.as_of/2" do
      assert [%{fields: fields, valid_from: @second, valid_to: @third}] =
               current(as_of: ~U[2026-02-15 00:00:00Z])

      assert fields == %{"name" => "Ada", "email" => "ada@example.com"}
    end

    test "an as_of on an observation's timestamp sees that observation" do
      assert [%{valid_from: @second}] = current(as_of: @second)
    end

    test "an as_of before the first observation returns no record" do
      assert [] = current(as_of: ~U[2025-12-31 00:00:00Z])
    end
  end

  test "observations that land out of order give the same history", %{app_id: app_id} do
    observe(app_id, "c1", %{"name" => "Ada Lovelace"}, @third)
    observe(app_id, "c1", %{"name" => "Ada"}, @first)
    observe(app_id, "c1", %{"email" => "ada@example.com"}, @second)

    assert [%{fields: %{"name" => "Ada", "email" => "ada@example.com"}}] =
             current(as_of: ~U[2026-02-15 00:00:00Z])

    assert [%{fields: %{"name" => "Ada Lovelace", "email" => "ada@example.com"}}] = current()
  end

  test "a relationship load made by the same read sees the same as_of", %{app_id: app_id} do
    observe(app_id, "c1", %{"name" => "Ada"}, @first)
    observe(app_id, "c2", %{"name" => "Grace"}, @second)
    observe(app_id, "c1", %{"name" => "Ada Lovelace"}, @third)

    assert [%{records: [%{legacy_id: "c1", fields: %{"name" => "Ada"}}]}] =
             LegacyApp
             |> Ash.Query.load(:records)
             |> Ash.Query.as_of(~U[2026-01-15 00:00:00Z])
             |> Ash.read!()

    assert [%{records: records}] =
             LegacyApp
             |> Ash.Query.load(records: Ash.Query.sort(LegacyRecords, :legacy_id))
             |> Ash.read!()

    assert [{"c1", "Ada Lovelace"}, {"c2", "Grace"}] =
             Enum.map(records, &{&1.legacy_id, &1.fields["name"]})
  end
end
