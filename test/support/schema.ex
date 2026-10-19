defmodule AshTypedSql.Test.Schema do
  @moduledoc false

  @statements [
    "create extension if not exists citext",
    "drop table if exists audit_log, orders, customers cascade",
    "drop type if exists customer_tier",
    "create type customer_tier as enum ('bronze', 'silver', 'gold')",
    """
    create table customers (
      id uuid primary key default gen_random_uuid(),
      name text not null,
      email citext,
      tier customer_tier not null default 'bronze',
      tags text[] not null default '{}',
      active boolean not null default true,
      settings jsonb,
      born_on date
    )
    """,
    """
    create table orders (
      id bigserial primary key,
      customer_id uuid not null references customers(id),
      total numeric not null,
      discount float8,
      inserted_at timestamptz not null default now(),
      shipped_at timestamp
    )
    """,
    "create table audit_log (id bigserial primary key, message text not null)",
    "create or replace function name_score(a text, b text) returns float8 immutable language sql as $$ select length(a)::float8 / greatest(length(b), 1) $$",
    "create or replace function is_vip(name text) returns boolean immutable language sql as $$ select name like 'VIP %' $$",
    "create sequence if not exists bump_seq",
    "create or replace function bump_counter() returns bigint volatile language sql as $$ select nextval('bump_seq') $$",
    "create or replace function half(x numeric) returns numeric immutable language sql as $$ select x / 2 $$",
    "create or replace function half(x float8) returns float8 immutable language sql as $$ select x / 2 $$",
    "create or replace function label_of(n int4) returns text immutable language sql as $$ select 'int ' || n $$",
    "create or replace function label_of(n int8) returns text immutable language sql as $$ select 'bigint ' || n $$",
    "create or replace function label_of(a text, b text) returns text immutable language sql as $$ select a || '/' || b $$",
    "create or replace function label_of(a anyelement, b anyelement, c anyelement) returns text immutable language sql as $$ select 'any' $$",
    "create or replace function label_of(variadic parts text[]) returns text immutable language sql as $$ select array_to_string(parts, ',') $$"
  ]

  def config do
    :ash_typed_sql
    |> Application.fetch_env!(AshTypedSql.Test.Repo)
    |> Keyword.take([:username, :password, :hostname, :database])
  end

  def reset! do
    {:ok, admin} = Postgrex.start_link(Keyword.put(config(), :database, "postgres"))
    database = Keyword.fetch!(config(), :database)

    case Postgrex.query(admin, ~s(create database "#{database}"), []) do
      {:ok, _} -> :ok
      {:error, %Postgrex.Error{postgres: %{code: :duplicate_database}}} -> :ok
    end

    GenServer.stop(admin)
    {:ok, conn} = Postgrex.start_link(config())
    Enum.each(@statements, &Postgrex.query!(conn, &1, []))

    Postgrex.query!(
      conn,
      File.read!("test/support/typed_sql/functions/business_days_between.sql"),
      []
    )

    GenServer.stop(conn)
  end
end
