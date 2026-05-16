defmodule Specodec.Parser do
  @moduledoc """
  Schema-driven generic encoder/decoder.
  ...
  """

  alias Specodec.{SpecReader, SpecWriter}

  # ── Schema helpers ────────────────────────────────────────────────────────

  def lookup_schema(schema, name) do
    case List.keyfind(schema, name, 0) do
      {^name, _atom, spec} -> spec
      nil -> nil
    end
  end

  # ── Decode ────────────────────────────────────────────────────────────────

  def decode_object(impl, state, schema, mod) when is_atom(mod) do
    state = impl.begin_object(state)
    {pairs, state} = decode_fields(impl, state, schema, [])
    state = impl.end_object(state)
    val = if schema == [] do
      apply(mod, :new, [])
    else
      # pairs = [{elixir_atom, val}, ...]
      struct(mod, pairs)
    end
    {val, state}
  end

  # Schema is a list of {wire_name, elixir_atom, type_spec} tuples.
  # Accumulator is a list of {elixir_atom, value} tuples.
  defp decode_fields(impl, state, schema, acc) do
    case impl.has_next_field?(state) do
      {true, state} ->
        {name, state} = impl.read_field_name(state)
        case List.keyfind(schema, name, 0) do
          nil ->
            state = impl.skip(state)
            decode_fields(impl, state, schema, acc)
          {_wire, _atom, {:enum, _opts}} ->
            {val, state} = impl.read_enum(state)
            decode_fields(impl, state, schema, [{_atom, val} | acc])
          {_wire, atom, {type, opts}} ->
            {val, state} = read_typed(impl, state, type, opts)
            decode_fields(impl, state, schema, [{atom, val} | acc])
        end
      {false, state} ->
        {Enum.reverse(acc), state}
    end
  end

  # ── Typed read dispatch ───────────────────────────────────────────────────

  # Entry: type and opts come separately from schema
  defp read_typed(impl, state, :optional, opts) do
    {inner_type, inner_opts} = opts[:inner]
    case impl.is_null?(state) do
      {true, state} -> {:ok, state} = impl.read_null(state); {nil, state}
      {false, state} -> read_typed(impl, state, inner_type, inner_opts)
    end
  end
  defp read_typed(impl, state, :string, _),       do: impl.read_string(state)
  defp read_typed(impl, state, :bool, _),         do: impl.read_bool(state)
  defp read_typed(impl, state, :int32, _),        do: impl.read_int32(state)
  defp read_typed(impl, state, :int64, _),        do: impl.read_int64(state)
  defp read_typed(impl, state, :uint32, _),       do: impl.read_uint32(state)
  defp read_typed(impl, state, :uint64, _),       do: impl.read_uint64(state)
  defp read_typed(impl, state, :float32, _),      do: impl.read_float32(state)
  defp read_typed(impl, state, :float64, _),      do: impl.read_float64(state)
  defp read_typed(impl, state, :bytes, _),        do: impl.read_bytes(state)
  defp read_typed(impl, state, :enum, _),         do: impl.read_enum(state)

  defp read_typed(impl, state, :model, opts) do
    case Keyword.get(opts, :required, true) do
      false ->
        case impl.is_null?(state) do
          {true, state} -> {:ok, state} = impl.read_null(state); {nil, state}
          {false, state} -> opts[:module].decode(impl, state)
        end
      true ->
        opts[:module].decode(impl, state)
    end
  end

  defp read_typed(impl, state, :union, opts) do
    case Keyword.get(opts, :required, true) do
      false ->
        case impl.is_null?(state) do
          {true, state} -> {:ok, state} = impl.read_null(state); {nil, state}
          {false, state} -> opts[:module].decode(impl, state)
        end
      true ->
        opts[:module].decode(impl, state)
    end
  end

  defp read_typed(impl, state, :array, opts) do
    {elem_type, elem_opts} = opts[:elem]
    SpecReader.read_array(impl, state, fn s ->
      read_typed(impl, s, elem_type, elem_opts)
    end)
  end

  defp read_typed(impl, state, :map, opts) do
    {elem_type, elem_opts} = opts[:elem]
    SpecReader.read_map(impl, state, fn s ->
      read_typed(impl, s, elem_type, elem_opts)
    end)
  end

  # ── Encode ────────────────────────────────────────────────────────────────

  def encode_object(impl, w, schema, obj) do
    # Schema is a list of {wire_name, elixir_atom, type_spec} tuples
    # Count required fields
    field_count = Enum.count(schema, fn {_wire, _atom, info} ->
      case info do
        {:optional, _} -> false
        {type, _opts} ->
          case type do
            {:model, kw} -> Keyword.get(kw, :required, true)
            {:union, kw} -> Keyword.get(kw, :required, true)
            _ -> true
          end
        _ -> true
      end
    end)

    optional_count = Enum.count(schema, fn {_wire, atom, info} ->
      val = Map.get(obj, atom)
      case info do
        {:optional, _} -> val != nil
        {type, _opts} ->
          case type do
            {:model, kw} -> Keyword.get(kw, :required) == false and val != nil
            {:union, kw} -> Keyword.get(kw, :required) == false and val != nil
            _ -> false
          end
        _ -> false
      end
    end)

    w = impl.begin_object(w, field_count + optional_count)

    Enum.reduce(schema, w, fn {wire_name, atom, info}, w_acc ->
      val = Map.get(obj, atom)
      case info do
        {:optional, opts} ->
          if val != nil do
            {inner_t, inner_opts} = opts[:inner]
            w_acc |> impl.write_field(wire_name) |> write_typed(impl, val, inner_t, inner_opts)
          else
            w_acc
          end
        {type, opts} ->
          case type do
            {:model, kw} ->
              if Keyword.get(kw, :required) == false and val == nil, do: w_acc,
                else: w_acc |> impl.write_field(wire_name) |> write_typed(impl, val, type, opts)
            {:union, kw} ->
              if Keyword.get(kw, :required) == false and val == nil, do: w_acc,
                else: w_acc |> impl.write_field(wire_name) |> write_typed(impl, val, type, opts)
            _ ->
              w_acc |> impl.write_field(wire_name) |> write_typed(impl, val, type, opts)
          end
      end
    end)
    |> then(&impl.end_object(&1))
  end

  # ── Typed write dispatch ──────────────────────────────────────────────────

  defp write_typed(w, impl, val, {type, _opts}), do: write_typed(w, impl, val, type, _opts)
  defp write_typed(w, impl, val, :optional, opts) when is_list(opts) do
    # Handled in encode_object - should not reach here
    w
  end
  defp write_typed(w, impl, val, :string, _),   do: impl.write_string(w, val)
  defp write_typed(w, impl, val, :bool, _),     do: impl.write_bool(w, val)
  defp write_typed(w, impl, val, :int32, _),    do: impl.write_int32(w, val)
  defp write_typed(w, impl, val, :int64, _),    do: impl.write_int64(w, val)
  defp write_typed(w, impl, val, :uint32, _),   do: impl.write_uint32(w, val)
  defp write_typed(w, impl, val, :uint64, _),   do: impl.write_uint64(w, val)
  defp write_typed(w, impl, val, :float32, _),  do: impl.write_float32(w, val)
  defp write_typed(w, impl, val, :float64, _),  do: impl.write_float64(w, val)
  defp write_typed(w, impl, val, :bytes, _),    do: impl.write_bytes(w, val)
  defp write_typed(w, impl, val, :enum, _),     do: impl.write_enum(w, val)
  defp write_typed(w, impl, val, :model, _opts) do
    val.__struct__.encode(impl, w, val)
  end
  defp write_typed(w, impl, val, :union, opts) do
    opts[:module].encode(impl, w, val)
  end
  defp write_typed(w, impl, val, :array, opts) do
    {elem_type, elem_opts} = opts[:elem]
    SpecWriter.write_array(impl, w, val, fn w2, item ->
      write_typed(w2, impl, item, elem_type, elem_opts)
    end)
  end
  defp write_typed(w, impl, val, :map, opts) do
    {elem_type, elem_opts} = opts[:elem]
    SpecWriter.write_map(impl, w, val, fn w2, item ->
      write_typed(w2, impl, item, elem_type, elem_opts)
    end)
  end

  # ── Union helpers ─────────────────────────────────────────────────────────

  def encode_union_value(impl, w, type, val) when is_tuple(type) do
    {t, opts} = type
    write_typed(w, impl, val, t, opts)
  end
  def encode_union_value(impl, w, type, val) do
    write_typed(w, impl, val, type, [])
  end

  def decode_union_value(impl, r, type) when is_tuple(type) do
    {t, opts} = type
    read_typed(impl, r, t, opts)
  end
  def decode_union_value(impl, r, type) do
    read_typed(impl, r, type, [])
  end
end
