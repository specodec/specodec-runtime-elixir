defmodule Specodec.GronReader do
  @moduledoc false
  @behaviour Specodec.SpecReader

  def new(text) when is_binary(text) do
    lines = String.split(text, "\n", trim: true) |> Enum.reject(&(String.trim(&1) == ""))
    {lines, 0, %{path: [], expect: :value}}
  end

  @impl true
  def begin_object({lines, cursor, ctx}) do
    {lines, cursor + 1, %{ctx | expect: :key_or_end}}
  end

  @impl true
  def has_next_field?({lines, cursor, ctx}) do
    if cursor >= length(lines) do
      {false, {lines, cursor, ctx}}
    else
      line = Enum.at(lines, cursor)
      {String.trim(line) != "};", {lines, cursor, ctx}}
    end
  end

  @impl true
  def read_field_name({lines, cursor, ctx}) do
    line = Enum.at(lines, cursor) |> String.trim()
    # Format: "obj.field = value;" or "  field = value;"
    case String.split(line, " = ", parts: 2) do
      [left, _] ->
        parts = String.split(left, ".")
        field = List.last(parts)
        {field, {lines, cursor, ctx}}
      _ ->
        {"", {lines, cursor, ctx}}
    end
  end

  @impl true
  def end_object({lines, cursor, ctx}) do
    {lines, cursor + 1, %{ctx | expect: :value}}
  end

  @impl true
  def begin_array({lines, cursor, ctx}) do
    {lines, cursor + 1, %{ctx | expect: :key_or_end}}
  end

  @impl true
  def has_next_element?({lines, cursor, ctx}) do
    if cursor >= length(lines) do
      {false, {lines, cursor, ctx}}
    else
      line = Enum.at(lines, cursor)
      {String.trim(line) != "];", {lines, cursor, ctx}}
    end
  end

  @impl true
  def end_array({lines, cursor, ctx}) do
    {lines, cursor + 1, %{ctx | expect: :value}}
  end

  @impl true
  def read_string({lines, cursor, ctx}) do
    line = Enum.at(lines, cursor)
    val = extract_value(line, :string)
    {val, {lines, cursor + 1, ctx}}
  end

  @impl true
  def read_bool({lines, cursor, ctx}) do
    line = Enum.at(lines, cursor)
    val = extract_value(line, :other)
    {val == "true", {lines, cursor + 1, ctx}}
  end

  @impl true
  def read_int32({lines, cursor, ctx}), do: read_gron_num(lines, cursor, ctx, &:erlang.trunc/1)
  @impl true
  def read_int64({lines, cursor, ctx}), do: read_gron_num(lines, cursor, ctx, &:erlang.trunc/1)
  @impl true
  def read_uint32({lines, cursor, ctx}), do: read_gron_num(lines, cursor, ctx, &:erlang.trunc/1)
  @impl true
  def read_uint64({lines, cursor, ctx}), do: read_gron_num(lines, cursor, ctx, &:erlang.trunc/1)
  @impl true
  def read_float32({lines, cursor, ctx}), do: read_gron_num(lines, cursor, ctx, & &1)
  @impl true
  def read_float64({lines, cursor, ctx}), do: read_gron_num(lines, cursor, ctx, & &1)

  defp read_gron_num(lines, cursor, ctx, convert) do
    line = Enum.at(lines, cursor)
    raw = extract_value(line, :other)
    # Handle quoted integers (int64/uint64)
    raw_unquoted = if String.starts_with?(raw, "\"") and String.ends_with?(raw, "\"") do
      String.slice(raw, 1..-2//1)
    else
      raw
    end
    case Integer.parse(raw_unquoted) do
      {i, _} -> {convert.(i), {lines, cursor + 1, ctx}}
      :error ->
        case Float.parse(raw_unquoted) do
          {f, _} -> {convert.(f), {lines, cursor + 1, ctx}}
          :error -> {0, {lines, cursor + 1, ctx}}
        end
    end
  end

  @impl true
  def read_null({lines, cursor, ctx}) do
    {:ok, {lines, cursor + 1, ctx}}
  end

  @impl true
  def read_bytes({lines, cursor, ctx}) do
    line = Enum.at(lines, cursor)
    raw = extract_value(line, :string)
    bytes = Base.decode64!(raw)
    {bytes, {lines, cursor + 1, ctx}}
  end

  @impl true
  def read_enum({lines, cursor, ctx}) do
    line = Enum.at(lines, cursor)
    val = extract_value(line, :string)
    {val, {lines, cursor + 1, ctx}}
  end

  @impl true
  def is_null?({lines, cursor, ctx}) do
    if cursor >= length(lines) do
      {true, {lines, cursor, ctx}}
    else
      line = Enum.at(lines, cursor)
      {String.contains?(line, "= null;"), {lines, cursor, ctx}}
    end
  end

  @impl true
  def skip({lines, cursor, ctx}) do
    {lines, cursor + 1, ctx}
  end

  # ── helpers ──

  defp extract_value(line, :string) do
    val = raw_value(line)
    # Remove trailing semicolon (may be before closing quote)
    val = String.replace(val, "\";", "\"") |> String.replace(";\"", "\"")
    val = String.trim_trailing(val, ";")
    val = String.trim(val)
    if String.starts_with?(val, "\"") and String.ends_with?(val, "\"") do
      unescape(String.slice(val, 1..-2//1))
    else
      val
    end
  end

  defp extract_value(line, :other) do
    raw_value(line)
    |> String.replace(~s(\";), "\"")
    |> String.replace(";", "")
    |> String.trim()
  end

  defp raw_value(line) do
    case String.split(line, " = ", parts: 2) do
      [_, rest] -> String.trim(rest)
      [only] -> String.trim(only, ";\" ")
    end
  end

  defp unescape(str) do
    str
    |> String.replace("\\\"", "\"")
    |> String.replace("\\\\", "\\")
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\r", "\r")
  end
end
