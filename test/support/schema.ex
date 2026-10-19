defmodule AshTypedSql.Test.Schema do
  @moduledoc false

  @statements [
    "create extension if not exists citext",
    "drop table if exists schema_migrations, audit_log, orders, customers cascade",
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
    "create table audit_log (id bigserial primary key, message text not null)"
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
    GenServer.stop(conn)
  end
end
