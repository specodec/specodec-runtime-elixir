defmodule Specodec.RyuMath do
  @moduledoc false

  import Bitwise

  def pow5bits(e) do
    div(e * 1217359, 524288) + 1
  end

  def log10_pow2(e) do
    div(e * 78913, 262144)
  end

  def log10_pow5(e) do
    div(e * 732923, 1048576)
  end

  def decimal_length9(v) when v >= 100000000, do: 9
  def decimal_length9(v) when v >= 10000000, do: 8
  def decimal_length9(v) when v >= 1000000, do: 7
  def decimal_length9(v) when v >= 100000, do: 6
  def decimal_length9(v) when v >= 10000, do: 5
  def decimal_length9(v) when v >= 1000, do: 4
  def decimal_length9(v) when v >= 100, do: 3
  def decimal_length9(v) when v >= 10, do: 2
  def decimal_length9(_v), do: 1

  def decimal_length17(v) when v >= 10000000000000000, do: 17
  def decimal_length17(v) when v >= 1000000000000000, do: 16
  def decimal_length17(v) when v >= 100000000000000, do: 15
  def decimal_length17(v) when v >= 10000000000000, do: 14
  def decimal_length17(v) when v >= 1000000000000, do: 13
  def decimal_length17(v) when v >= 100000000000, do: 12
  def decimal_length17(v) when v >= 10000000000, do: 11
  def decimal_length17(v) when v >= 1000000000, do: 10
  def decimal_length17(v) when v >= 100000000, do: 9
  def decimal_length17(v) when v >= 10000000, do: 8
  def decimal_length17(v) when v >= 1000000, do: 7
  def decimal_length17(v) when v >= 100000, do: 6
  def decimal_length17(v) when v >= 10000, do: 5
  def decimal_length17(v) when v >= 1000, do: 4
  def decimal_length17(v) when v >= 100, do: 3
  def decimal_length17(v) when v >= 10, do: 2
  def decimal_length17(_v), do: 1

  def mul_shift_32(m, factor, shift) do
    factor_lo = factor &&& 0xFFFFFFFF
    factor_hi = factor >>> 32

    bits0 = m * factor_lo
    bits1 = m * factor_hi

    sum_val = (bits0 >>> 32) + bits1
    (sum_val >>> (shift - 32)) &&& 0xFFFFFFFF
  end

  def mul_shift_64(m, {lo, hi}, shift) do
    b0 = m * lo
    b2 = m * hi

    b0_hi = b0 >>> 64

    sum_val = b0_hi + b2
    (sum_val >>> (shift - 64)) &&& 0xFFFFFFFFFFFFFFFF
  end

  def multiple_of_power_of_5_32(_value, 0), do: true
  def multiple_of_power_of_5_32(value, q) when q >= 32, do: value == 0
  def multiple_of_power_of_5_32(value, q) do
    pow5 = Integer.pow(5, q)
    rem(value, pow5) == 0
  end

  def multiple_of_power_of_2_32(_value, 0), do: true
  def multiple_of_power_of_2_32(value, q) when q >= 32, do: value == 0
  def multiple_of_power_of_2_32(value, q) do
    (value &&& ((1 <<< q) - 1)) == 0
  end

  def multiple_of_power_of_5_64(_value, 0), do: true
  def multiple_of_power_of_5_64(value, q) when q >= 64, do: value == 0
  def multiple_of_power_of_5_64(value, q) do
    pow5 = Integer.pow(5, q)
    rem(value, pow5) == 0
  end

  def multiple_of_power_of_2_64(_value, 0), do: true
  def multiple_of_power_of_2_64(value, q) when q >= 64, do: value == 0
  def multiple_of_power_of_2_64(value, q) do
    (value &&& ((1 <<< q) - 1)) == 0
  end
end
