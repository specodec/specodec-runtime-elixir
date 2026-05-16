defmodule Specodec.MsgPackWriter do
  @moduledoc """
  MsgPack binary writer. State is an IO list of binaries for efficient concatenation.
  """

  @behaviour Specodec.SpecWriter

  import Bitwise

  def new, do: []

  @impl true
  def write_string(state, value) do
    encoded = value |> String.to_charlist() |> :unicode.characters_to_binary(:utf8)
    length = byte_size(encoded)
    state =
      cond do
        length <= 0x1F ->
          [state | <<0xA0 ||| length>>]
        length <= 0xFF ->
          [state | <<0xD9, length::8>>]
        length <= 0xFFFF ->
          [state | <<0xDA, length::16-big>>]
        true ->
          [state | <<0xDB, length::32-big>>]
      end
    [state | encoded]
  end

  @impl true
  def write_bool(state, true), do: [state | <<0xC3>>]
  def write_bool(state, false), do: [state | <<0xC2>>]

  @impl true
  def write_int32(state, value) do
    cond do
      value >= 0 and value <= 0x7F ->
        [state | <<value>>]
      value >= -0x20 and value < 0 ->
        [state | <<value &&& 0xFF>>]
      value >= 0 and value <= 0xFF ->
        [state | <<0xCC, value::8>>]
      value >= 0 and value <= 0xFFFF ->
        [state | <<0xCD, value::16-big>>]
      value >= 0 ->
        [state | <<0xCE, value::32-big>>]
      value >= -0x80 ->
        [state | <<0xD0, (value &&& 0xFF)::8>>]
      value >= -0x8000 ->
        [state | <<0xD1, (value &&& 0xFFFF)::16-big>>]
      true ->
        [state | <<0xD2, (value &&& 0xFFFFFFFF)::32-big>>]
    end
  end

  @impl true
  def write_int64(state, value) do
    cond do
      value >= 0 and value <= 0x7F ->
        [state | <<value>>]
      value >= -0x20 and value < 0 ->
        [state | <<value &&& 0xFF>>]
      value >= 0 and value <= 0xFF ->
        [state | <<0xCC, value::8>>]
      value >= 0 and value <= 0xFFFF ->
        [state | <<0xCD, value::16-big>>]
      value >= 0 and value <= 0xFFFFFFFF ->
        [state | <<0xCE, value::32-big>>]
      value >= 0 ->
        [state | <<0xCF, value::64-big>>]
      value >= -0x80 ->
        [state | <<0xD0, (value &&& 0xFF)::8>>]
      value >= -0x8000 ->
        [state | <<0xD1, (value &&& 0xFFFF)::16-big>>]
      value >= -0x80000000 ->
        [state | <<0xD2, (value &&& 0xFFFFFFFF)::32-big>>]
      true ->
        [state | <<0xD3, (value &&& 0xFFFFFFFFFFFFFFFF)::64-big>>]
    end
  end

  @impl true
  def write_uint32(state, value) do
    cond do
      value <= 0x7F ->
        [state | <<value>>]
      value <= 0xFF ->
        [state | <<0xCC, value::8>>]
      value <= 0xFFFF ->
        [state | <<0xCD, value::16-big>>]
      true ->
        [state | <<0xCE, value::32-big>>]
    end
  end

  @impl true
  def write_uint64(state, value) do
    cond do
      value <= 0x7F ->
        [state | <<value>>]
      value <= 0xFF ->
        [state | <<0xCC, value::8>>]
      value <= 0xFFFF ->
        [state | <<0xCD, value::16-big>>]
      value <= 0xFFFFFFFF ->
        [state | <<0xCE, value::32-big>>]
      true ->
        [state | <<0xCF, value::64-big>>]
    end
  end

  @impl true
  def write_float32(state, :nan), do: [state | <<0xCA, 0x7FC00000::32-big>>]
  def write_float32(state, :infinity), do: [state | <<0xCA, 0x7F800000::32-big>>]
  def write_float32(state, :neg_infinity), do: [state | <<0xCA, 0xFF800000::32-big>>]
  def write_float32(state, value) when is_float(value) do
    <<bits::32-native>> = <<value::float-32-native>>
    [state | <<0xCA, bits::32-big>>]
  end

  @impl true
  def write_float64(state, :nan), do: [state | <<0xCB, 0x7FF8000000000000::64-big>>]
  def write_float64(state, :infinity), do: [state | <<0xCB, 0x7FF0000000000000::64-big>>]
  def write_float64(state, :neg_infinity), do: [state | <<0xCB, 0xFFF0000000000000::64-big>>]
  def write_float64(state, value) when is_float(value) do
    <<bits::64-native>> = <<value::float-64-native>>
    [state | <<0xCB, bits::64-big>>]
  end

  @impl true
  def write_null(state) do
    [state | <<0xC0>>]
  end

  @impl true
  def write_bytes(state, value) do
    length = byte_size(value)
    state =
      cond do
        length <= 0xFF ->
          [state | <<0xC4, length::8>>]
        length <= 0xFFFF ->
          [state | <<0xC5, length::16-big>>]
        true ->
          [state | <<0xC6, length::32-big>>]
      end
    [state | value]
  end

  @impl true
  def write_enum(state, value), do: write_string(state, value)

  @impl true
  def begin_object(state, field_count) do
    cond do
      field_count <= 0x0F ->
        [state | <<0x80 ||| field_count>>]
      field_count <= 0xFFFF ->
        [state | <<0xDE, field_count::16-big>>]
      true ->
        [state | <<0xDF, field_count::32-big>>]
    end
  end

  @impl true
  def write_field(state, name), do: write_string(state, name)

  @impl true
  def end_object(state), do: state

  @impl true
  def begin_array(state, element_count) do
    cond do
      element_count <= 0x0F ->
        [state | <<0x90 ||| element_count>>]
      element_count <= 0xFFFF ->
        [state | <<0xDC, element_count::16-big>>]
      true ->
        [state | <<0xDD, element_count::32-big>>]
    end
  end

  @impl true
  def next_element(state), do: state

  @impl true
  def end_array(state), do: state

  @impl true
  def to_bytes(state) do
    IO.iodata_to_binary(state)
  end
end
