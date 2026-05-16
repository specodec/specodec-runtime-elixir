defmodule Specodec.MsgPackReader do
  @moduledoc """
  MsgPack binary reader using Elixir binary pattern matching.
  State is {binary, stack_list} where binary is remaining bytes
  and stack_list tracks array/map nesting counts.
  """

  import Bitwise

  @behaviour Specodec.SpecReader

  defmodule StackEntry do
    defstruct [:type, :count]
  end

  def new(binary) when is_binary(binary), do: {binary, []}

  @impl true
  def begin_object({data, stack}) do
    {count, data} = read_map_header(data)
    {data, [%StackEntry{type: :map, count: count} | stack]}
  end

  @impl true
  def has_next_field?({_data, [%StackEntry{type: :map, count: count} | _rest]} = state) do
    {count > 0, state}
  end

  def has_next_field?(state), do: {false, state}

  @impl true
  def read_field_name({data, [%StackEntry{type: :map} = top | rest]}) do
    {name, data} = read_string_val(data)
    {name, {data, [top | rest]}}
  end

  @impl true
  def end_object({data, [_entry | rest]}), do: dec_top({data, rest})

  @impl true
  def begin_array({data, stack}) do
    {count, data} = read_array_header(data)
    {data, [%StackEntry{type: :array, count: count} | stack]}
  end

  @impl true
  def has_next_element?({_data, [%StackEntry{type: :array, count: count} | _rest]} = state) do
    {count > 0, state}
  end

  def has_next_element?(state), do: {false, state}

  @impl true
  def end_array({data, [_entry | rest]}), do: dec_top({data, rest})

  @impl true
  def read_string({data, stack}) do
    {str, data} = read_string_val(data)
    {str, dec_top({data, stack})}
  end

  @impl true
  def read_bool({data, stack}) do
    {bool, data} = read_bool_val(data)
    {bool, dec_top({data, stack})}
  end

  @impl true
  def read_int32({data, stack}) do
    {int, data} = read_integer(data)
    {int, dec_top({data, stack})}
  end

  @impl true
  def read_int64({data, stack}) do
    {int, data} = read_integer(data)
    {int, dec_top({data, stack})}
  end

  @impl true
  def read_uint32({data, stack}) do
    {int, data} = read_integer(data)
    {int, dec_top({data, stack})}
  end

  @impl true
  def read_uint64({data, stack}) do
    {int, data} = read_integer(data)
    {int, dec_top({data, stack})}
  end

  @impl true
  def read_float32({data, stack}) do
    case data do
      <<0xCA, bits::32-big, rest::binary>> ->
        {bits_to_float32(bits), dec_top({rest, stack})}
      <<byte, _rest::binary>> ->
        raise "Expected float32 marker 0xCA, got 0x#{Integer.to_string(byte, 16)}"
    end
  end

  @impl true
  def read_float64({data, stack}) do
    case data do
      <<0xCB, bits::64-big, rest::binary>> ->
        {bits_to_float64(bits), dec_top({rest, stack})}
      <<byte, _rest::binary>> ->
        raise "Expected float64 marker 0xCB, got 0x#{Integer.to_string(byte, 16)}"
    end
  end

  # Convert IEEE 754 bits to float (handles NaN/Inf that Elixir binary matching rejects)
  defp bits_to_float32(bits) do
    sign = (bits >>> 31) &&& 1
    exponent = (bits >>> 23) &&& 0xFF
    fraction = bits &&& 0x7FFFFF
    cond do
      exponent == 0xFF and fraction != 0 -> :nan
      exponent == 0xFF and sign == 0 -> :infinity
      exponent == 0xFF and sign == 1 -> :neg_infinity
      true ->
        <<f::float-32-native>> = <<bits::32-native>>
        f
    end
  end

  defp bits_to_float64(bits) do
    sign = (bits >>> 63) &&& 1
    exponent = (bits >>> 52) &&& 0x7FF
    fraction = bits &&& 0xFFFFFFFFFFFFF
    cond do
      exponent == 0x7FF and fraction != 0 -> :nan
      exponent == 0x7FF and sign == 0 -> :infinity
      exponent == 0x7FF and sign == 1 -> :neg_infinity
      true ->
        <<f::float-64-native>> = <<bits::64-native>>
        f
    end
  end

  @impl true
  def read_null({data, stack}) do
    case data do
      <<0xC0, rest::binary>> -> {:ok, dec_top({rest, stack})}
      <<byte, _rest::binary>> -> raise "Expected nil marker 0xC0, got 0x#{Integer.to_string(byte, 16)}"
    end
  end

  @impl true
  def read_bytes({data, stack}) do
    case data do
      <<0xC4, len::8, bytes::binary-size(len), rest::binary>> ->
        {bytes, dec_top({rest, stack})}
      <<0xC5, len::16-big, bytes::binary-size(len), rest::binary>> ->
        {bytes, dec_top({rest, stack})}
      <<0xC6, len::32-big, bytes::binary-size(len), rest::binary>> ->
        {bytes, dec_top({rest, stack})}
      _ ->
        raise "Expected bin marker"
    end
  end

  @impl true
  def read_enum({data, stack}) do
    {str, data} = read_string_val(data)
    {str, dec_top({data, stack})}
  end

  @impl true
  def is_null?({data, _stack} = state) do
    case data do
      <<0xC0, _rest::binary>> -> {true, state}
      _ -> {false, state}
    end
  end

  @impl true
  def skip({data, stack}) do
    {_value, data} = skip_value(data)
    dec_top({data, stack})
  end

  # ── Public helper: consume one value from the counter ────────────────────

  @doc "Decrement the top counter without consuming bytes. Use after reading a composite value."
  def consume_one(state), do: dec_top(state)

  # ── Decrement top stack counter ──────────────────────────────────────────

  defp dec_top({data, [%StackEntry{count: n} = top | rest]}) when n > 0 do
    {data, [%StackEntry{top | count: n - 1} | rest]}
  end
  defp dec_top(state), do: state

  # ── Map header parsing ────────────────────────────────────────────────────

  defp read_map_header(<<0xDE, count::16-big, rest::binary>>), do: {count, rest}
  defp read_map_header(<<0xDF, count::32-big, rest::binary>>), do: {count, rest}
  defp read_map_header(<<byte, rest::binary>>) when byte >= 0x80 and byte < 0x90 do
    {byte - 0x80, rest}
  end
  defp read_map_header(data) do
    {0, data}
  end

  # ── Array header parsing ──────────────────────────────────────────────────

  defp read_array_header(<<0xDC, count::16-big, rest::binary>>), do: {count, rest}
  defp read_array_header(<<0xDD, count::32-big, rest::binary>>), do: {count, rest}
  defp read_array_header(<<byte, rest::binary>>) when byte >= 0x90 and byte < 0xA0 do
    {byte - 0x90, rest}
  end
  defp read_array_header(data) do
    {0, data}
  end

  # ── String reading ────────────────────────────────────────────────────────

  defp read_string_val(<<0xD9, len::8, str::binary-size(len), rest::binary>>), do: {str, rest}
  defp read_string_val(<<0xDA, len::16-big, str::binary-size(len), rest::binary>>), do: {str, rest}
  defp read_string_val(<<0xDB, len::32-big, str::binary-size(len), rest::binary>>), do: {str, rest}
  defp read_string_val(<<byte, rest::binary>>) when byte >= 0xA0 and byte < 0xC0 do
    len = byte - 0xA0
    <<str::binary-size(len), rest::binary>> = rest
    {str, rest}
  end
  defp read_string_val(data) do
    {"", data}
  end

  # ── Bool reading ──────────────────────────────────────────────────────────

  defp read_bool_val(<<0xC2, rest::binary>>), do: {false, rest}
  defp read_bool_val(<<0xC3, rest::binary>>), do: {true, rest}
  defp read_bool_val(data) do
    {false, data}
  end

  # ── Integer reading ───────────────────────────────────────────────────────

  defp read_integer(<<0xCC, val::8, rest::binary>>), do: {val, rest}
  defp read_integer(<<0xCD, val::16-big, rest::binary>>), do: {val, rest}
  defp read_integer(<<0xCE, val::32-big, rest::binary>>), do: {val, rest}
  defp read_integer(<<0xCF, val::64-big, rest::binary>>), do: {val, rest}
  defp read_integer(<<0xD0, val::8-signed, rest::binary>>), do: {val, rest}
  defp read_integer(<<0xD1, val::16-signed-big, rest::binary>>), do: {val, rest}
  defp read_integer(<<0xD2, val::32-signed-big, rest::binary>>), do: {val, rest}
  defp read_integer(<<0xD3, val::64-signed-big, rest::binary>>), do: {val, rest}
  defp read_integer(<<byte, rest::binary>>) when (byte &&& 0x80) == 0, do: {byte, rest}
  defp read_integer(<<byte, rest::binary>>) when (byte &&& 0xE0) == 0xE0, do: {byte - 256, rest}

  # ── Skip / value skipping ─────────────────────────────────────────────────

  # nil, false, true
  defp skip_value(<<0xC0, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xC2, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xC3, rest::binary>>), do: {nil, rest}

  # float
  defp skip_value(<<0xCA, _f::float-size(32)-big, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xCB, _f::float-size(64)-big, rest::binary>>), do: {nil, rest}

  # uint 8/16/32/64
  defp skip_value(<<0xCC, _val::8, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xCD, _val::16-big, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xCE, _val::32-big, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xCF, _val::64-big, rest::binary>>), do: {nil, rest}

  # int 8/16/32/64
  defp skip_value(<<0xD0, _val::8, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xD1, _val::16-big, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xD2, _val::32-big, rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xD3, _val::64-big, rest::binary>>), do: {nil, rest}

  # fixext
  defp skip_value(<<0xD4, _val::binary-size(1), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xD5, _val::binary-size(2), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xD6, _val::binary-size(4), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xD7, _val::binary-size(8), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xD8, _val::binary-size(16), rest::binary>>), do: {nil, rest}

  # ext 8/16/32
  defp skip_value(<<0xC7, len::8, _data::binary-size(len + 1), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xC8, len::16-big, _data::binary-size(len + 1), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xC9, len::32-big, _data::binary-size(len + 1), rest::binary>>), do: {nil, rest}

  # bin 8/16/32
  defp skip_value(<<0xC4, len::8, _bytes::binary-size(len), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xC5, len::16-big, _bytes::binary-size(len), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xC6, len::32-big, _bytes::binary-size(len), rest::binary>>), do: {nil, rest}

  # str 8/16/32
  defp skip_value(<<0xD9, len::8, _str::binary-size(len), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xDA, len::16-big, _str::binary-size(len), rest::binary>>), do: {nil, rest}
  defp skip_value(<<0xDB, len::32-big, _str::binary-size(len), rest::binary>>), do: {nil, rest}

  # array 16/32
  defp skip_value(<<0xDC, count::16-big, rest::binary>>), do: skip_array(rest, count)
  defp skip_value(<<0xDD, count::32-big, rest::binary>>), do: skip_array(rest, count)

  # map 16/32
  defp skip_value(<<0xDE, count::16-big, rest::binary>>), do: skip_map(rest, count)
  defp skip_value(<<0xDF, count::32-big, rest::binary>>), do: skip_map(rest, count)

  # fixmap
  defp skip_value(<<byte, rest::binary>>) when byte >= 0x80 and byte < 0x90 do
    skip_map(rest, byte - 0x80)
  end

  # fixarray
  defp skip_value(<<byte, rest::binary>>) when byte >= 0x90 and byte < 0xA0 do
    skip_array(rest, byte - 0x90)
  end

  # fixstr
  defp skip_value(<<byte, rest::binary>>) when byte >= 0xA0 and byte < 0xC0 do
    len = byte - 0xA0
    <<_str::binary-size(len), rest::binary>> = rest
    {nil, rest}
  end

  # positive/negative fixint
  defp skip_value(<<_byte, rest::binary>>), do: {nil, rest}

  defp skip_array(data, 0), do: {nil, data}
  defp skip_array(data, count) do
    {_val, data} = skip_value(data)
    skip_array(data, count - 1)
  end

  defp skip_map(data, 0), do: {nil, data}
  defp skip_map(data, count) do
    {_key, data} = skip_value(data)
    {_val, data} = skip_value(data)
    skip_map(data, count - 1)
  end
end
