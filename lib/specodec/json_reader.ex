defmodule Specodec.JsonReader do
  @moduledoc false
  @behaviour Specodec.SpecReader

  def new(binary) when is_binary(binary), do: {binary, 0, [], nil}

  defp skip_ws(s, pos) do
    case s do
      <<_::binary-size(pos), ch, _::binary>> when ch in ' \t\n\r' -> skip_ws(s, pos + 1)
      _ -> {pos, safe_char(s, pos)}
    end
  end

  defp safe_char(s, pos) do
    case s do <<_::binary-size(pos), ch, _::binary>> -> ch; _ -> nil end
  end

  defp skip_comma({s, pos, stack, fe}) do
    {pos2, ch} = skip_ws(s, pos)
    if ch == ?,, do: {s, pos2 + 1, stack, fe}, else: {s, pos2, stack, fe}
  end

  @impl true
  def begin_object({s, pos, stack, _fe}) do
    {pos2, _} = skip_ws(s, pos)
    {s, pos2 + 1, [{:object, 1} | stack], nil}
  end

  @impl true
  def has_next_field?({s, pos, stack, fe} = st) do
    {pos2, ch} = skip_ws(s, pos)
    if ch == ?, do
      {pos3, _} = skip_ws(s, pos2 + 1)
      {true, {s, pos3, stack, fe}}
    else
      {ch != ?}, st}
    end
  end

  @impl true
  def read_field_name({s, pos, [{:object, _} | _] = stack, fe}) do
    {key, pos2} = parse_string(s, pos)
    {pos3, _} = skip_ws(s, pos2)
    {key, {s, pos3 + 1, [{:object, 0} | tl(stack)], fe}}
  end

  @impl true
  def end_object({s, pos, [_ | stack], fe}) do
    {pos2, _} = skip_ws(s, pos)
    {s, pos2 + 1, stack, fe}
  end

  @impl true
  def begin_array({s, pos, stack, _fe}) do
    {pos2, _} = skip_ws(s, pos)
    {s, pos2 + 1, [{:array, 1} | stack], nil}
  end

  @impl true
  def has_next_element?({s, pos, stack, fe} = st) do
    {pos2, ch} = skip_ws(s, pos)
    if ch == ?, do
      {pos3, _} = skip_ws(s, pos2 + 1)
      {true, {s, pos3, stack, fe}}
    else
      {ch != ?], st}
    end
  end

  @impl true
  def end_array({s, pos, [_ | stack], fe}) do
    {pos2, _} = skip_ws(s, pos)
    {s, pos2 + 1, stack, fe}
  end

  @impl true
  def read_string(state) do
    {s, pos, stack, fe} = skip_comma(state)
    {str, pos2} = parse_string(s, pos)
    {str, {s, pos2, stack, fe}}
  end

  @impl true
  def read_bool(state) do
    {s, pos, stack, fe} = skip_comma(state)
    {val, pos2} = case s do
      <<_::binary-size(pos), "true", _::binary>> -> {true, pos + 4}
      _ -> {false, pos + 5}
    end
    {val, {s, pos2, stack, fe}}
  end

  @impl true
  def read_int32(state), do: read_num(state, &:erlang.trunc/1)

  @impl true
  def read_int64(state) do
    {s, pos, stack, fe} = skip_comma(state)
    {pos2, ch} = skip_ws(s, pos)
    if ch == ?" do
      {str, pos3} = parse_string(s, pos2)
      {String.to_integer(str), {s, pos3, stack, fe}}
    else
      {raw, pos3} = extract_number(s, pos2)
      {f, _} = Float.parse(raw)
      {trunc(f), {s, pos3, stack, fe}}
    end
  end

  @impl true
  def read_uint32(state), do: read_num(state, &:erlang.trunc/1)

  @impl true
  def read_uint64(state) do
    {s, pos, stack, fe} = skip_comma(state)
    {pos2, ch} = skip_ws(s, pos)
    if ch == ?" do
      {str, pos3} = parse_string(s, pos2)
      {String.to_integer(str), {s, pos3, stack, fe}}
    else
      {raw, pos3} = extract_number(s, pos2)
      {f, _} = Float.parse(raw)
      {trunc(f), {s, pos3, stack, fe}}
    end
  end

  @impl true
  def read_float32(state), do: read_num(state, & &1)
  @impl true
  def read_float64(state), do: read_num(state, & &1)

  defp read_num(state, convert) do
    {s, pos, stack, fe} = skip_comma(state)
    {raw, pos2} = extract_number(s, pos)
    {f, _} = Float.parse(raw)
    {convert.(f), {s, pos2, stack, fe}}
  end

  defp extract_number(s, pos) do
    start = pos
    pos = if safe_char(s, pos) == ?-, do: pos + 1, else: pos
    pos = consume_digits(s, pos)
    pos = if safe_char(s, pos) == ?., do: consume_digits(s, pos + 1), else: pos
    pos = if safe_char(s, pos) in [?E, ?e] do
      pos = pos + 1
      pos = if safe_char(s, pos) in [?+, ?-], do: pos + 1, else: pos
      consume_digits(s, pos)
    else pos
    end
    {String.slice(s, start, pos - start), pos}
  end

  defp consume_digits(s, pos) do
    case s do
      <<_::binary-size(pos), ch, _::binary>> when ch in ?0..?9 -> consume_digits(s, pos + 1)
      _ -> pos
    end
  end

  @impl true
  def read_null(state) do
    {s, pos, stack, fe} = skip_comma(state)
    {:ok, {s, pos + 4, stack, fe}}
  end

  @impl true
  def read_bytes(state) do
    {str, state2} = read_string(state)
    {Base.decode64!(str), state2}
  end

  @impl true
  def read_enum(state), do: read_string(state)

  @impl true
  def is_null?({s, pos, _stack, _fe} = st) do
    case s do
      <<_::binary-size(pos), "null", _::binary>> -> {true, st}
      _ -> {false, st}
    end
  end

  @impl true
  def skip({s, pos, stack, fe}) do
    {_, pos2} = skip_value(s, pos)
    {s, pos2, stack, fe}
  end

  defp parse_string(s, pos) do
    {str, pos2} = parse_string_content(s, pos + 1, [])
    {IO.iodata_to_binary(Enum.reverse(str)), pos2 + 1}
  end

  defp parse_string_content(s, pos, acc) do
    case s do
      <<_::binary-size(pos), ?", _::binary>> -> {acc, pos}
      <<_::binary-size(pos), ?\\, _::binary>> ->
        {ch, pos2} = parse_escape(s, pos + 1)
        parse_string_content(s, pos2, [ch | acc])
      <<_::binary-size(pos), ch, _::binary>> ->
        parse_string_content(s, pos + 1, [ch | acc])
    end
  end

  defp parse_escape(s, pos) do
    case s do
      <<_::binary-size(pos), ch, _::binary>> when ch in '\"\\/bfnrt' -> {escape_char(ch), pos + 1}
      <<_::binary-size(pos), ?u, hex::binary-size(4), _::binary>> ->
        cp = String.to_integer(hex, 16)
        if cp >= 0xD800 and cp <= 0xDBFF do
          <<_::binary-size(pos + 6), ?\\, ?u, hex2::binary-size(4), _::binary>> = s
          low = String.to_integer(hex2, 16)
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
          {cp, pos + 12}
        else
          {cp, pos + 6}
        end
    end
  end

  defp escape_char(?"), do: ?"
  defp escape_char(?\\), do: ?\\
  defp escape_char(?/), do: ?/
  defp escape_char(?b), do: ?\b
  defp escape_char(?f), do: ?\f
  defp escape_char(?n), do: ?\n
  defp escape_char(?r), do: ?\r
  defp escape_char(?t), do: ?\t

  defp skip_value(s, pos) do
    {_, ch} = skip_ws(s, pos)
    case ch do
      ?" -> {_, pos2} = parse_string(s, pos); {nil, pos2}
      ?{ -> skip_nested(s, pos + 1, ?}, 1)
      ?[ -> skip_nested(s, pos + 1, ?], 1)
      ?t -> {nil, pos + 4}
      ?f -> {nil, pos + 5}
      ?n -> {nil, pos + 4}
      nil -> {nil, pos}
      _ -> {_, pos2} = extract_number(s, pos); {nil, pos2}
    end
  end

  defp skip_nested(s, pos, _closer, 0), do: {nil, pos + 1}
  defp skip_nested(s, pos, closer, depth) do
    {_, pos2} = skip_value(s, pos)
    {_, ch} = skip_ws(s, pos2)
    cond do
      ch == ?, -> skip_nested(s, pos2 + 1, closer, depth)
      ch == closer -> skip_nested(s, pos2, closer, depth - 1)
      ch == opposite(closer) -> skip_nested(s, pos2, closer, depth + 1)
      true -> {nil, pos2}
    end
  end

  defp opposite(?}), do: ?{
  defp opposite(?]), do: ?[
end
