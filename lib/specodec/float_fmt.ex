defmodule Specodec.FloatFmt do
  @moduledoc false

  alias Specodec.{RyuF32, RyuF64}

  def ryu_f32_to_string(:nan), do: "NaN"
  def ryu_f32_to_string(:infinity), do: "Infinity"
  def ryu_f32_to_string(:neg_infinity), do: "-Infinity"
  def ryu_f32_to_string(value) when is_float(value) do
    RyuF32.float32_to_string(value)
  end
  def ryu_f32_to_string(value) when is_integer(value) do
    RyuF32.float32_to_string(value / 1)
  end

  def ryu_f64_to_string(:nan), do: "NaN"
  def ryu_f64_to_string(:infinity), do: "Infinity"
  def ryu_f64_to_string(:neg_infinity), do: "-Infinity"
  def ryu_f64_to_string(value) when is_float(value) do
    RyuF64.float64_to_string(value)
  end
  def ryu_f64_to_string(value) when is_integer(value) do
    RyuF64.float64_to_string(value / 1)
  end
end
