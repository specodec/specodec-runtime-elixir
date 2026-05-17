defmodule SpecodecTest.RyuTest do
  use ExUnit.Case

  @test_dir Path.join(__DIR__, "ryu")

  defp load_lines(filename) do
    Path.join(@test_dir, filename)
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
  end

  defp load_expected(filename) do
    Path.join(@test_dir, filename)
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
  end

  defp parse_float(str) do
    cond do
      str == "NaN" -> :nan
      str == "Infinity" -> :infinity
      str == "-Infinity" -> :neg_infinity
      true ->
        case Float.parse(str) do
          {v, ""} -> v
          {v, _} -> v
          :error -> 0.0
        end
    end
  end

  test "Ryu F32 original" do
    inputs = load_lines("test_cases_f32.txt")
    expected = load_expected("expected_f32.txt")

    pairs = Enum.zip(inputs, expected) |> Enum.to_list()

    {passed, failed} =
      Enum.reduce(pairs, {0, 0}, fn {inp, exp}, {p, f} ->
        val = parse_float(inp)
        result = Specodec.FloatFmt.ryu_f32_to_string(val)
        if result == exp, do: {p + 1, f}, else: {p, f + 1}
      end)

    assert failed == 0, "#{failed} F32 failures"
    IO.puts(:stderr, "#{passed}/#{length(pairs)} f32 original")
  end

  test "Ryu F64 original" do
    inputs = load_lines("test_cases_f64.txt")
    expected = load_expected("expected_f64.txt")

    pairs = Enum.zip(inputs, expected) |> Enum.to_list()

    {passed, failed} =
      Enum.reduce(pairs, {0, 0}, fn {inp, exp}, {p, f} ->
        val = parse_float(inp)
        result = Specodec.FloatFmt.ryu_f64_to_string(val)
        if result == exp, do: {p + 1, f}, else: {p, f + 1}
      end)

    assert failed == 0, "#{failed} F64 failures"
    IO.puts(:stderr, "#{passed}/#{length(pairs)} f64 original")
  end

  test "Ryu F32 table coverage" do
    inputs = load_lines("test_cases_table_coverage.txt")
    expected = load_expected("expected_table_coverage.txt")

    pairs = Enum.zip(inputs, expected) |> Enum.to_list()

    {passed, failed} =
      Enum.reduce(pairs, {0, 0}, fn {line, exp}, {p, f} ->
        [raw | _] = String.split(line)
        val = case Float.parse(raw) do
          {v, _} -> v
          :error -> 0.0
        end
        result = Specodec.FloatFmt.ryu_f32_to_string(val)
        if result == exp, do: {p + 1, f}, else: {p, f + 1}
      end)

    assert failed == 0, "#{failed} F32 table coverage failures"
    IO.puts(:stderr, "#{passed}/#{length(pairs)} f32 table coverage")
  end

  test "Ryu F64 table coverage" do
    inputs = load_lines("test_cases_f64_table_coverage.txt")
    expected = load_expected("expected_f64_table_coverage.txt")

    pairs = Enum.zip(inputs, expected) |> Enum.to_list()

    {passed, failed} =
      Enum.reduce(pairs, {0, 0}, fn {line, exp}, {p, f} ->
        [raw | _] = String.split(line)
        val = case Float.parse(raw) do
          {v, _} -> v
          :error -> 0.0
        end
        result = Specodec.FloatFmt.ryu_f64_to_string(val)
        if result == exp, do: {p + 1, f}, else: {p, f + 1}
      end)

    assert failed == 0, "#{failed} F64 table coverage failures"
    IO.puts(:stderr, "#{passed}/#{length(pairs)} f64 table coverage")
  end

  test "Ryu total summary" do
    IO.puts("=== TOTAL: Ryu tests complete (see stderr for details) ===")
    assert true
  end
end
