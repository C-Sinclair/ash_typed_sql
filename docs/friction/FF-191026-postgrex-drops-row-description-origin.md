**When:** 2026-10-19
**Where:** `AshTypedSql.Codegen.Describe`, DD-001 staging 1 spike
**Versions:** postgrex 0.22.4, Elixir 1.19.1, OTP 28, Postgres 17.11
**Upstream:** reportable

## What happened

DD-001 expected `Postgrex.prepare/4` to expose each result column's source table OID and attribute number. `Postgrex.Messages` decodes both into the `row_field` record, but `Postgrex.Protocol` keeps only `type_oid`, `name` and `type_mod` when it builds `Postgrex.Query`. The public struct has `param_oids`, `columns` and `result_oids`, and no column origin.

## The signal

No error. `%Postgrex.Query{}` has no field for the table OID or attnum. `Postgrex.Protocol` maps `row_field(type_oid: oid, type_mod: mod, name: name) -> {oid, name, mod}` and discards the rest.

## What it cost

Reading `postgrex/lib/postgrex/protocol.ex` and `messages.ex`, then writing a decoder. Mostly time spent reading.

## What we did instead

`AshTypedSql.Codegen.Describe` calls `Postgrex.Protocol.connect/1` for the startup and authentication handshake, which is `@moduledoc false`. It then sets the socket to `active: false`, sends `Parse`, `Describe ('S')` and `Sync` itself, and decodes `ParameterDescription` and `RowDescription` from the wire. It never calls `Postgrex.Protocol.disconnect/2`, because that deletes an ETS table owned by the connecting process. It sends `Terminate` and closes the socket instead. The private dependency is confined to `connect/1` and the `sock` field of its returned state.

## What would fix it

Postgrex keeping `table_oid` and `column` per result column on `Postgrex.Query`, for example as `result_origins`. That turns `Describe` into a call to `Postgrex.prepare/4`.
