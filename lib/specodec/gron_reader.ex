defmodule Specodec.GronReader do
  @moduledoc false
  @behaviour Specodec.SpecReader

  # State: {lines, cursor, ctx}
  # ctx is a list of %{prefix: ..., type: ...} maps (top of stack last)
  # Lines are raw text lines, parsed on the fly.

  def new(text) when is_binary(text) do
    lines = String.split(text, "\n", trim: true) |> Enum.reject(&(String.trim(&1) == ""))
    {lines, 0, []}
  end

  # ── Object ───────────────────────────────────────────────────────────────────

  @impl true
  def begin_object({lines, cursor, ctx}) do
    line = Enum.at(lines, cursor) |> String.trim()
    _path = line_path(line)
    {lines, cursor + 1, [%{prefix: line_path(line), type: :object} | ctx]}
  end

  @impl true
  def has_next_field?({lines, cursor, ctx}) do
    if ctx == [] or cursor >= length(lines) do
      {false, {lines, cursor, ctx}}
    else
      pfx = ctx |> hd() |> Map.get(:prefix)
      path = line_path(Enum.at(lines, cursor))
      has = String.starts_with?(path, pfx <> ".")
      rem = if has, do: String.slice(path, byte_size(pfx) + 1..-1//1), else: ""
      has = has and not String.contains?(rem, ".") and not String.contains?(rem, "[")
      {has, {lines, cursor, ctx}}
    end
  end

  @impl true
  def read_field_name({lines, cursor, ctx}) do
    pfx = ctx |> hd() |> Map.get(:prefix)
    path = line_path(Enum.at(lines, cursor))
    name = String.slice(path, byte_size(pfx) + 1..-1//1)
    {name, {lines, cursor, ctx}}
  end

  @impl true
  def end_object({lines, cursor, ctx}) do
    [_top | rest] = ctx
    {lines, cursor, rest}
  end

  # ── Array ────────────────────────────────────────────────────────────────────

  @impl true
  def begin_array({lines, cursor, ctx}) do
    line = Enum.at(lines, cursor) |> String.trim()
    {lines, cursor + 1, [%{prefix: line_path(line), type: :array, index: -1} | ctx]}
  end

  @impl true
  def has_next_element?({lines, cursor, ctx}) do
    if ctx == [] or cursor >= length(lines) do
      {false, {lines, cursor, ctx}}
    else
      top = ctx |> hd()
      ni = top.index + 1
      exp = "#{top.prefix}[#{ni}]"
      path = line_path(Enum.at(lines, cursor))
      has = path == exp or String.starts_with?(path, exp <> ".") or String.starts_with?(path, exp <> "[")
      {has, {lines, cursor, _new_top = %{top | index: ni} |> then(&[&1 | tl(ctx)])}}
    end
  end

  @impl true
  def end_array({lines, cursor, ctx}) do
    [_top | rest] = ctx
    {lines, cursor, rest}
  end

  # ── Scalar reads ─────────────────────────────────────────────────────────────

  @impl true
  def read_string({lines, cursor, ctx}) do
    val = extract_value(Enum.at(lines, cursor), :string)
    {val, {lines, cursor + 1, ctx}}
  end

  @impl true
  def read_bool({lines, cursor, ctx}) do
    val = extract_value(Enum.at(lines, cursor), :other)
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
    raw = extract_value(Enum.at(lines, cursor), :other)
    raw_unquoted = if String.starts_with?(raw, "\"") and String.ends_with?(raw, "\"") do
      String.slice(raw, 1..-2//1)
    else
      raw
    end
    case Integer.parse(raw_unquoted) do
      {i, rest} when rest == "" -> {convert.(i), {lines, cursor + 1, ctx}}
      _ ->
        case Float.parse(raw_unquoted) do
          {f, rest} when rest == "" -> {convert.(f), {lines, cursor + 1, ctx}}
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
    raw = extract_value(Enum.at(lines, cursor), :string)
    bytes = Base.decode64!(raw)
    {bytes, {lines, cursor + 1, ctx}}
  end

  @impl true
  def read_enum({lines, cursor, ctx}) do
    val = extract_value(Enum.at(lines, cursor), :string)
    {val, {lines, cursor + 1, ctx}}
  end

  @impl true
  def is_null?({lines, cursor, ctx}) do
    if cursor >= length(lines) do
      {true, {lines, cursor, ctx}}
    else
      {String.contains?(Enum.at(lines, cursor), "= null;"), {lines, cursor, ctx}}
    end
  end

  @impl true
  def skip({lines, cursor, ctx}) do
    sp = line_path(Enum.at(lines, cursor))
    pos = skip_nested(lines, sp, cursor + 1, length(lines))
    {lines, pos, ctx}
  end

  defp skip_nested(_lines, _sp, pos, len) when pos >= len, do: pos
  defp skip_nested(lines, sp, pos, len) do
    np = line_path(Enum.at(lines, pos))
    deeper = byte_size(np) > byte_size(sp) and
      (String.starts_with?(np, sp <> ".") or String.starts_with?(np, sp <> "["))
    if deeper, do: skip_nested(lines, sp, pos + 1, len), else: pos
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp line_path(line) do
    case String.split(line, " = ", parts: 2) do
      [left, _] -> String.trim(left)
      _ -> ""
    end
  end

  defp extract_value(line, :string) do
    val = raw_value(line)
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
    unescape_chars(str, 0, byte_size(str), [])
  end

  defp unescape_chars(str, i, len, acc) when i >= len, do: IO.iodata_to_binary(Enum.reverse(acc))

  defp unescape_chars(str, i, len, acc) do
    case :binary.at(str, i) do
      ch when ch == ?\\ and i + 1 < len ->
        next = :binary.at(str, i + 1)
        case next do
          ?" -> unescape_chars(str, i + 2, len, [?" | acc])
          ?\\ -> unescape_chars(str, i + 2, len, [?\\ | acc])
          ?/ -> unescape_chars(str, i + 2, len, [?/ | acc])
          ?b -> unescape_chars(str, i + 2, len, [?\b | acc])
          ?f -> unescape_chars(str, i + 2, len, [?\f | acc])
          ?n -> unescape_chars(str, i + 2, len, [?\n | acc])
          ?r -> unescape_chars(str, i + 2, len, [?\r | acc])
          ?t -> unescape_chars(str, i + 2, len, [?\t | acc])
          ?u when i + 6 <= len ->
            hex = binary_part(str, i + 2, 4)
            cp = String.to_integer(hex, 16)
            if cp >= 0xD800 and cp <= 0xDBFF and i + 12 <= len and binary_part(str, i + 6, 2) == "\\u" do
              hex2 = binary_part(str, i + 8, 4)
              low = String.to_integer(hex2, 16)
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
              unescape_chars(str, i + 12, len, [<<cp::utf8>> | acc])
            else
              unescape_chars(str, i + 6, len, [<<cp::utf8>> | acc])
            end
          _ -> unescape_chars(str, i + 1, len, acc)
        end
      _ ->
        unescape_chars(str, i + 1, len, [:binary.at(str, i) | acc])
    end
  end
end
