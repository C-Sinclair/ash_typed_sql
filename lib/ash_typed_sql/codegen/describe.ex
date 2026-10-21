defmodule AshTypedSql.Codegen.Describe do
  @moduledoc """
  Sends one statement to Postgres as Parse + Describe and returns what Postgres reports about it.

  Each result column carries its source table OID and attribute number, which are zero for computed columns. Postgrex drops those two fields from its public `Postgrex.Query`, so this module reads the `RowDescription` message itself (see `docs/friction/FF-191026-postgrex-drops-row-description-origin.md`).
  """

  @type column :: %{
          name: String.t(),
          type_oid: non_neg_integer(),
          table_oid: non_neg_integer(),
          attnum: integer()
        }
  @type t :: %{param_oids: [non_neg_integer()], columns: [column()]}

  @doc "Opens a describe-only connection with the same options as `Postgrex.start_link/1`."
  def connect(opts) do
    opts
    |> Keyword.put_new(:types, Postgrex.DefaultTypes)
    |> Keyword.put_new(:hostname, "localhost")
    |> Keyword.put_new(:port, 5432)
    |> Keyword.put_new(:username, System.get_env("PGUSER") || System.get_env("USER"))
    |> Postgrex.Protocol.connect()
  end

  def disconnect(%{sock: {mod, sock}}) do
    _ = mod.send(sock, message(?X, []))
    mod.close(sock)
  end

  @spec describe(term(), String.t()) :: {:ok, t()} | {:error, map()}
  def describe(%{sock: {mod, sock}}, sql) do
    :ok = setopts(mod, sock, active: false)

    :ok =
      mod.send(sock, [message(?P, [0, sql, 0, <<0::16>>]), message(?D, [?S, 0]), message(?S, [])])

    receive_until_ready(mod, sock, "", %{param_oids: [], columns: []}, nil)
  end

  defp setopts(:gen_tcp, sock, opts), do: :inet.setopts(sock, opts)
  defp setopts(:ssl, sock, opts), do: :ssl.setopts(sock, opts)

  defp message(type, body) do
    body = IO.iodata_to_binary(body)
    <<type, byte_size(body) + 4::32, body::binary>>
  end

  defp receive_until_ready(mod, sock, buffer, acc, error) do
    case buffer do
      <<type, len::32, rest::binary>> when byte_size(rest) >= len - 4 ->
        <<body::binary-size(len - 4), rest::binary>> = rest

        case type do
          ?Z -> if error, do: {:error, error}, else: {:ok, acc}
          ?t -> receive_until_ready(mod, sock, rest, %{acc | param_oids: param_oids(body)}, error)
          ?T -> receive_until_ready(mod, sock, rest, %{acc | columns: columns(body)}, error)
          ?E -> receive_until_ready(mod, sock, rest, acc, error_fields(body))
          _ -> receive_until_ready(mod, sock, rest, acc, error)
        end

      _ ->
        {:ok, data} = mod.recv(sock, 0)
        receive_until_ready(mod, sock, buffer <> data, acc, error)
    end
  end

  defp param_oids(<<_count::16, oids::binary>>), do: for(<<oid::32 <- oids>>, do: oid)

  defp columns(<<_count::16, rest::binary>>), do: decode_columns(rest)

  defp decode_columns(""), do: []

  defp decode_columns(binary) do
    [name, rest] = :binary.split(binary, <<0>>)

    <<table_oid::32, attnum::signed-16, type_oid::32, _len::16, _mod::32, _fmt::16, rest::binary>> =
      rest

    [
      %{name: name, type_oid: type_oid, table_oid: table_oid, attnum: attnum}
      | decode_columns(rest)
    ]
  end

  defp error_fields(body) do
    body
    |> :binary.split(<<0>>, [:global, :trim_all])
    |> Map.new(fn <<code, value::binary>> -> {<<code>>, value} end)
    |> then(&%{message: &1["M"], code: &1["C"], position: &1["P"]})
  end

  @doc """
  Returns the `file:line:column: ` prefix for a Postgres error `position` in `sql`, or `file: ` when Postgres gave none.

  `position` is the 1-based character offset Postgres reports. `offset` counts characters of the file that precede `sql`, such as leading whitespace codegen trimmed off.
  """
  @spec location(String.t(), String.t(), String.t() | integer() | nil, non_neg_integer()) ::
          String.t()
  def location(file, sql, position, offset \\ 0)

  def location(file, _sql, nil, _offset), do: "#{file}: "

  def location(file, sql, position, offset) when is_binary(position),
    do: location(file, sql, String.to_integer(position), offset)

  def location(file, sql, position, offset) do
    before = String.slice(sql, 0, position - 1 + offset)
    lines = String.split(before, "\n")
    "#{file}:#{length(lines)}:#{String.length(List.last(lines)) + 1}: "
  end
end
