defmodule Specodec.GronWriter do
  @moduledoc """
  GRON writer. Convert values to GRON text lines.
  Tracks path components and writes each leaf as `path = value;`.
  Uses 2-space indent per nesting level.
  """

  @behaviour Specodec.SpecWriter

  import Bitwise
  alias Specodec.FloatFmt

  def new, do: {[], ["json"], []}

  @impl true
  def write_string(state, value), do: emit(state, ~s("#{escape(value)}"))
  def   write_bool(state, true), do: emit(state, "true")

  @impl true
  def write_bool(state, false), do: emit(state, "false")

  @impl true
  def write_int32(state, value), do: emit(state, Integer.to_string(value))

  @impl true
  def write_int64(state, value), do: emit(state, ~s("#{value}"))

  @impl true
  def write_uint32(state, value), do: emit(state, Integer.to_string(value))

  @impl true
  def write_uint64(state, value), do: emit(state, ~s("#{value}"))

  @impl true
  def write_float32(state, value) do
    emit(state, float32_repr(value))
  end

  @impl true
  def write_float64(state, value) do
    emit(state, float64_repr(value))
  end

  @impl true
  def write_null(state), do: emit(state, "null")

  @impl true
  def write_bytes(state, value) do
    encoded = Base.encode64(value)
    emit(state, ~s("#{encoded}"))
  end

  @impl true
  def write_enum(state, value), do: emit(state, ~s("#{escape(value)}"))

  @impl true
  def begin_object({lines, segments, nesting}, _field_count) do
    path = build_path(segments)
    {["#{path} = {};" | lines], segments, [%{depth: length(segments)} | nesting]}
  end

  @impl true
  def begin_array({lines, segments, nesting}, _element_count) do
    path = build_path(segments)
    {["#{path} = [];" | lines], segments, [%{depth: length(segments), array_index: -1} | nesting]}
  end

  @impl true
  def write_field({lines, segments, [top | rest_nesting]}, name) do
    segments =
      if length(segments) > top.depth do
        List.replace_at(segments, -1, name)
      else
        segments ++ [name]
      end
    {lines, segments, [top | rest_nesting]}
  end

  @impl true
  def end_object({lines, segments, nesting}) do
    [info | rest] = nesting
    new_segments = Enum.take(segments, info.depth)
    {lines, new_segments, rest}
  end

  @impl true
  def begin_array({lines, segments, nesting}, _element_count) do
    path = build_path(segments)
    lines = [lines | "#{path} = [];"]
    {lines, segments, [%{depth: length(segments), array_index: -1} | nesting]}
  end

  @impl true
  def next_element({lines, segments, nesting}) do
    [top | rest] = nesting
    new_index = top.array_index + 1
    seg = "[#{new_index}]"
    segments =
      if length(segments) > top.depth do
        List.replace_at(segments, -1, seg)
      else
        segments ++ [seg]
      end
    {lines, segments, [%{top | array_index: new_index} | rest]}
  end

  @impl true
  def end_array({lines, segments, nesting}) do
    [info | rest] = nesting
    new_segments = Enum.take(segments, info.depth)
    {lines, new_segments, rest}
  end

  @impl true
  def to_bytes({lines, _segments, _nesting}) do
    lines
    |> Enum.reverse()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp build_path(segments) do
    [head | tail] = segments
    Enum.reduce(tail, head, fn s, acc ->
      if String.starts_with?(s, "[") do
        acc <> s
      else
        acc <> "." <> s
      end
    end)
  end

  defp emit({lines, segments, nesting}, raw) do
    path = build_path(segments)
    {["#{path} = #{raw};" | lines], segments, nesting}
  end

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

  defp float32_repr(:nan), do: ~s("NaN")
  defp float32_repr(:infinity), do: ~s("Infinity")
  defp float32_repr(:neg_infinity), do: ~s("-Infinity")
  defp float32_repr(value) when is_float(value) do
    cond do
      is_nan_f32(value) -> ~s("NaN")
      is_inf_f32(value) -> ~s("Infinity")
      is_neg_inf_f32(value) -> ~s("-Infinity")
      true -> FloatFmt.ryu_f32_to_string(value)
    end
  end

  defp float64_repr(:nan), do: ~s("NaN")
  defp float64_repr(:infinity), do: ~s("Infinity")
  defp float64_repr(:neg_infinity), do: ~s("-Infinity")
  defp float64_repr(value) when is_float(value) do
    cond do
      is_nan_f64(value) -> ~s("NaN")
      is_inf_f64(value) -> ~s("Infinity")
      is_neg_inf_f64(value) -> ~s("-Infinity")
      true -> FloatFmt.ryu_f64_to_string(value)
    end
  end

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
