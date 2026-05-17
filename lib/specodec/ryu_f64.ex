defmodule Specodec.RyuF64 do
  @moduledoc false

  import Bitwise
  alias Specodec.{TablesF64, RyuMath}

  @mantissa_bits 52
  @bias 1023

  def float64_to_string(d) when is_float(d) do
    <<bits::64-big>> = <<d::float-64-big>>
    _float64_to_string(bits)
  end

  defp _float64_to_string(bits) do
    sign = (bits >>> 63) != 0
    ieee_mantissa = bits &&& 0xFFFFFFFFFFFFF
    ieee_exponent = (bits >>> 52) &&& 0x7FF

    cond do
      ieee_exponent == 0x7FF ->
        if ieee_mantissa == 0 do
          if sign, do: "-Infinity", else: "Infinity"
        else
          "NaN"
        end

      ieee_exponent == 0 and ieee_mantissa == 0 ->
        if sign, do: "-0E0", else: "0E0"

      true ->
        ryu_core(sign, ieee_exponent, ieee_mantissa)
    end
  end

  defp ryu_core(sign, ieee_exponent, ieee_mantissa) do
    {e2, m2} = if ieee_exponent == 0 do
      {1 - @bias - @mantissa_bits - 2, ieee_mantissa}
    else
      {ieee_exponent - @bias - @mantissa_bits - 2, (1 <<< @mantissa_bits) ||| ieee_mantissa}
    end

    even = (m2 &&& 1) == 0
    accept_bounds = even

    mv = 4 * m2
    mp = 4 * m2 + 2
    mm_shift = if ieee_mantissa != 0 or ieee_exponent <= 1, do: 1, else: 0
    mm = 4 * m2 - 1 - mm_shift

    vr_is_trailing_zeros = false
    vm_is_trailing_zeros = false
    last_digit = 0

    {vr, vp, vm, e10, vr_is_trailing_zeros, vm_is_trailing_zeros, last_digit} =
      if e2 >= 0 do
        pow5_inv_bitcount = TablesF64.pow5_inv_bitcount()
        q = RyuMath.log10_pow2(e2)
        e10 = q
        k = pow5_inv_bitcount + RyuMath.pow5bits(q) - 1
        i = -e2 + q + k

        inv_split = TablesF64.pow5_inv_split()
        {factor_lo, factor_hi} = Enum.at(inv_split, q)

        vr = RyuMath.mul_shift_64(mv, {factor_lo, factor_hi}, i)
        vp = RyuMath.mul_shift_64(mp, {factor_lo, factor_hi}, i)
        vm = RyuMath.mul_shift_64(mm, {factor_lo, factor_hi}, i)

        {vr, vp, vm, ld} =
          if q != 0 and div(vp - 1, 10) <= div(vm, 10) do
            l = pow5_inv_bitcount + RyuMath.pow5bits(q - 1) - 1
            {fl, fh} = Enum.at(inv_split, q - 1)
            ld = rem(RyuMath.mul_shift_64(mv, {fl, fh}, -e2 + q - 1 + l), 10)
            {vr, vp, vm, ld}
          else
            {vr, vp, vm, 0}
          end

        {vr_tz, vm_tz, vp} =
          if q <= 21 do
            if rem(mv, 5) == 0 do
              {RyuMath.multiple_of_power_of_5_64(mv, q), false, vp}
            else
              cond do
                accept_bounds ->
                  {false, RyuMath.multiple_of_power_of_5_64(mm, q), vp}
                true ->
                  new_vp = if RyuMath.multiple_of_power_of_5_64(mp, q), do: vp - 1, else: vp
                  {false, false, new_vp}
              end
            end
          else
            {false, false, vp}
          end

        {vr, vp, vm, e10, vr_tz, vm_tz, ld}

      else
        q = RyuMath.log10_pow5(-e2)
        e10 = q + e2
        i = -e2 - q
        k = RyuMath.pow5bits(i) - TablesF64.pow5_bitcount()
        j = q - k

        pow5_split = TablesF64.pow5_split()
        {factor_lo, factor_hi} = Enum.at(pow5_split, i)

        vr = RyuMath.mul_shift_64(mv, {factor_lo, factor_hi}, j)
        vp = RyuMath.mul_shift_64(mp, {factor_lo, factor_hi}, j)
        vm = RyuMath.mul_shift_64(mm, {factor_lo, factor_hi}, j)

        {vr, vp, vm, ld} =
          if q != 0 and div(vp - 1, 10) <= div(vm, 10) do
            j2 = q - 1 - (RyuMath.pow5bits(i + 1) - TablesF64.pow5_bitcount())
            {fl, fh} = Enum.at(pow5_split, i + 1)
            ld = rem(RyuMath.mul_shift_64(mv, {fl, fh}, j2), 10)
            {vr, vp, vm, ld}
          else
            {vr, vp, vm, 0}
          end

        {vr_tz, vm_tz, vp} =
          cond do
            q <= 1 ->
              new_vp = if accept_bounds, do: vp, else: vp - 1
              {true, if(accept_bounds, do: mm_shift == 1, else: false), new_vp}
            q < 63 ->
              new_vp = if accept_bounds do
                vp
              else
                if RyuMath.multiple_of_power_of_5_64(mp, q), do: vp - 1, else: vp
              end
              {RyuMath.multiple_of_power_of_2_64(mv, q - 1),
               if(accept_bounds, do: RyuMath.multiple_of_power_of_5_64(mm, q), else: false),
               new_vp}
            true ->
              {false, false, vp}
          end

        {vr, vp, vm, e10, vr_tz, vm_tz, ld}
      end

    removed = 0
    {vr3, vp3, vm3, last_digit, removed} = remove_trailing(
      vr, vp, vm, vr_is_trailing_zeros, vm_is_trailing_zeros,
      last_digit, accept_bounds, removed
    )

    exp = e10 + removed
    output = vr3
    olength = RyuMath.decimal_length17(output)

    result = if sign, do: "-", else: ""
    digits = Integer.to_string(output)
    result = result <>
      if olength == 1 do
        digits
      else
        {first, rest} = String.split_at(digits, 1)
        first <> "." <> rest
      end

    final_exp = exp + olength - 1
    result <> "E" <> Integer.to_string(final_exp)
  end

  defp remove_trailing(vr, vp, vm, vr_tz, vm_tz, last_digit, accept_bounds, removed) do
    if vm_tz or vr_tz do
      {vr2, vp2, vm2, last_digit, removed, vm_tz, vr_tz} =
        reduce_while(vr, vp, vm, vr_tz, vm_tz, last_digit, removed)

      round_up = (vr2 == vm2 and (not accept_bounds or not vm_tz)) or last_digit >= 5
      output = if round_up, do: vr2 + 1, else: vr2
      {output, vp2, vm2, last_digit, removed}
    else
      {vr2, vp2, vm2, last_digit, removed} =
        simple_reduce(vr, vp, vm, last_digit, removed)
      output = if vr2 == vm2 or last_digit >= 5, do: vr2 + 1, else: vr2
      {output, vp2, vm2, last_digit, removed}
    end
  end

  defp reduce_while(vr, vp, vm, vr_tz, vm_tz, last_digit, removed) do
    {vr2, vp2, vm2, last_digit, removed, vm_tz, vr_tz} =
      while_cond(vr, vp, vm, vr_tz, vm_tz, last_digit, removed)

    {vr3, vp3, vm3, last_digit, removed, vr_tz} =
      if vm_tz do
        while_vm_tz(vr2, vp2, vm2, vr_tz, last_digit, removed)
      else
        {vr2, vp2, vm2, last_digit, removed, vr_tz}
      end

    vr_tz_final = vr_tz && last_digit == 5 && rem(vr3, 2) == 0
    last_digit = if vr_tz_final, do: 4, else: last_digit

    {vr3, vp3, vm3, last_digit, removed, vm_tz, vr_tz}
  end

  defp while_cond(vr, vp, vm, vr_tz, vm_tz, last_digit, removed) do
    if div(vp, 10) > div(vm, 10) do
      vm_tz = vm_tz && rem(vm, 10) == 0
      vr_tz = vr_tz && last_digit == 0
      last_digit = rem(vr, 10)
      vr2 = div(vr, 10)
      vp2 = div(vp, 10)
      vm2 = div(vm, 10)
      while_cond(vr2, vp2, vm2, vr_tz, vm_tz, last_digit, removed + 1)
    else
      {vr, vp, vm, last_digit, removed, vm_tz, vr_tz}
    end
  end

  defp while_vm_tz(vr, vp, vm, vr_tz, last_digit, removed) do
    if rem(vm, 10) == 0 do
      vr_tz = vr_tz && last_digit == 0
      last_digit = rem(vr, 10)
      vr2 = div(vr, 10)
      vp2 = div(vp, 10)
      vm2 = div(vm, 10)
      while_vm_tz(vr2, vp2, vm2, vr_tz, last_digit, removed + 1)
    else
      {vr, vp, vm, last_digit, removed, vr_tz}
    end
  end

  defp simple_reduce(vr, vp, vm, last_digit, removed) do
    if div(vp, 10) > div(vm, 10) do
      last_digit = rem(vr, 10)
      vr2 = div(vr, 10)
      vp2 = div(vp, 10)
      vm2 = div(vm, 10)
      simple_reduce(vr2, vp2, vm2, last_digit, removed + 1)
    else
      {vr, vp, vm, last_digit, removed}
    end
  end
end
