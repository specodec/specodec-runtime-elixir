defmodule Specodec.JsonWriter do
  @moduledoc """
  JSON writer. State is an IO list for efficient concatenation.
  Writes compact JSON with no whitespace.
  """

  @behaviour Specodec.SpecWriter

  import Bitwise
  alias Specodec.FloatFmt

  def new, do: {[], []}

  @impl true
  def write_string({parts, first_item}, value) do
    escaped = escape(value)
    {[parts | [?", escaped, ?"]], first_item}
  end

  @impl true
  def write_bool({parts, first_item}, true), do: {[parts | "true"], first_item}
  def write_bool({parts, first_item}, false), do: {[parts | "false"], first_item}

  @impl true
  def write_int32({parts, first_item}, value) do
    {[parts | Integer.to_string(value)], first_item}
  end

  @impl true
  def write_int64({parts, first_item}, value) do
    {[parts | [?", Integer.to_string(value), ?"]], first_item}
  end

  @impl true
  def write_uint32({parts, first_item}, value) do
    {[parts | Integer.to_string(value)], first_item}
  end

  @impl true
  def write_uint64({parts, first_item}, value) do
    {[parts | [?", Integer.to_string(value), ?"]], first_item}
  end

  @impl true
  def write_float32({parts, first_item}, :nan), do: {[parts | ~s("NaN")], first_item}
  def write_float32({parts, first_item}, :infinity), do: {[parts | ~s("Infinity")], first_item}
  def write_float32({parts, first_item}, :neg_infinity), do: {[parts | ~s("-Infinity")], first_item}
  def write_float32({parts, first_item}, value) do
    result =
      cond do
        is_nan_f32(value) -> ~s("NaN")
        is_inf_f32(value) -> ~s("Infinity")
        is_neg_inf_f32(value) -> ~s("-Infinity")
        true -> FloatFmt.ryu_f32_to_string(value)
      end
    {[parts | result], first_item}
  end

  @impl true
  def write_float64({parts, first_item}, :nan), do: {[parts | ~s("NaN")], first_item}
  def write_float64({parts, first_item}, :infinity), do: {[parts | ~s("Infinity")], first_item}
  def write_float64({parts, first_item}, :neg_infinity), do: {[parts | ~s("-Infinity")], first_item}
  def write_float64({parts, first_item}, value) do
    result =
      cond do
        is_nan_f64(value) -> ~s("NaN")
        is_inf_f64(value) -> ~s("Infinity")
        is_neg_inf_f64(value) -> ~s("-Infinity")
        true -> FloatFmt.ryu_f64_to_string(value)
      end
    {[parts | result], first_item}
  end

  @impl true
  def write_null({parts, first_item}) do
    {[parts | "null"], first_item}
  end

  @impl true
  def write_bytes({parts, first_item}, value) do
    encoded = Base.encode64(value)
    {[parts | [?", encoded, ?"]], first_item}
  end

  @impl true
  def write_enum({parts, first_item}, value) do
    escaped = escape(value)
    {[parts | [?", escaped, ?"]], first_item}
  end

  @impl true
  def begin_object({parts, first_item}, _field_count) do
    {[parts | "{"], [true | first_item]}
  end

  @impl true
  def write_field({parts, [top | rest]}, name) do
    parts = if not top, do: [parts | ","], else: parts
    escaped = escape(name)
    {[parts | [?", escaped, ?", ?:]], [false | rest]}
  end

  @impl true
  def end_object({parts, [_top | rest]}) do
    {[parts | "}"], rest}
  end

  @impl true
  def begin_array({parts, first_item}, _size) do
    {[parts | "["], [true | first_item]}
  end

  @impl true
  def next_element({parts, [top | rest]}) do
    parts = if not top, do: [parts | ","], else: parts
    {parts, [false | rest]}
  end

  @impl true
  def end_array({parts, [_top | rest]}) do
    {[parts | "]"], rest}
  end

  @impl true
  def to_bytes({parts, _first_item}) do
    IO.iodata_to_binary(parts)
  end

  # ── String escaping ────────────────────────────────────────────────────────

  defp escape(str) do
    escape_chars(String.to_charlist(str), [])
  end

  defp escape_chars([], acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp escape_chars([c | rest], acc) do
    {part, continue} =
      case c do
        ?" -> {"\\\"", rest}
        ?\\ -> {"\\\\", rest}
        ?\b -> {"\\b", rest}
        ?\f -> {"\\f", rest}
        ?\n -> {"\\n", rest}
        ?\r -> {"\\r", rest}
        ?\t -> {"\\t", rest}
        c when c < 0x20 ->
          hex = Integer.to_string(c, 16) |> String.pad_leading(4, "0")
          {"\\u#{hex}", rest}
        c ->
          {<<c::utf8>>, rest}
      end
    escape_chars(continue, [part | acc])
  end

  # ── NaN/Infinity detection ─────────────────────────────────────────────────

  defp is_nan_f32(value) do
    <<bits::32>> = <<value::float-32-big>>
    (bits &&& 0x7F800000) == 0x7F800000 and (bits &&& 0x007FFFFF) != 0
  end

  defp is_inf_f32(value) do
    <<bits::32>> = <<value::float-32-big>>
    bits == 0x7F800000
  end

  defp is_neg_inf_f32(value) do
    <<bits::32>> = <<value::float-32-big>>
    bits == 0xFF800000
  end

  defp is_nan_f64(value) do
    <<bits::64>> = <<value::float-64-big>>
    (bits &&& 0x7FF0000000000000) == 0x7FF0000000000000 and (bits &&& 0x000FFFFFFFFFFFFF) != 0
  end

  defp is_inf_f64(value) do
    <<bits::64>> = <<value::float-64-big>>
    bits == 0x7FF0000000000000
  end

  defp is_neg_inf_f64(value) do
    <<bits::64>> = <<value::float-64-big>>
    bits == 0xFFF0000000000000
  end
end
