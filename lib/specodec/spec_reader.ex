defmodule Specodec.SpecReader do
  @moduledoc """
  Behaviour for binary-to-struct readers (MsgPack, JSON, Gron).

  Each reader implementation is a module that implements these callbacks.
  The reader state is passed as the first argument to most callbacks.
  """

  @type reader_state :: term()

  @callback begin_object(reader_state()) :: reader_state()
  @callback has_next_field?(reader_state()) :: {boolean(), reader_state()}
  @callback read_field_name(reader_state()) :: {String.t(), reader_state()}
  @callback end_object(reader_state()) :: reader_state()
  @callback begin_array(reader_state()) :: reader_state()
  @callback has_next_element?(reader_state()) :: {boolean(), reader_state()}
  @callback end_array(reader_state()) :: reader_state()
  @callback read_string(reader_state()) :: {String.t(), reader_state()}
  @callback read_bool(reader_state()) :: {boolean(), reader_state()}
  @callback read_int32(reader_state()) :: {integer(), reader_state()}
  @callback read_int64(reader_state()) :: {integer(), reader_state()}
  @callback read_uint32(reader_state()) :: {integer(), reader_state()}
  @callback read_uint64(reader_state()) :: {integer(), reader_state()}
  @callback read_float32(reader_state()) :: {float(), reader_state()}
  @callback read_float64(reader_state()) :: {float(), reader_state()}
  @callback read_null(reader_state()) :: {:ok, reader_state()}
  @callback read_bytes(reader_state()) :: {binary(), reader_state()}
  @callback read_enum(reader_state()) :: {String.t(), reader_state()}
  @callback is_null?(reader_state()) :: {boolean(), reader_state()}
  @callback skip(reader_state()) :: reader_state()

  # ── Helper: Read array ────────────────────────────────────────────────────

  @doc "Read a list by repeatedly calling the element read function"
  @spec read_array(module(), reader_state(), (reader_state() -> {term(), reader_state()})) :: {list(term()), reader_state()}
  def read_array(impl, state, read_elem_fun) do
    state = impl.begin_array(state)
    {list, state} = read_array_loop(impl, state, read_elem_fun, [])
    state = impl.end_array(state)
    {Enum.reverse(list), state}
  end

  @doc "Read a map (string keys) by repeatedly calling the value read function"
  @spec read_map(module(), reader_state(), (reader_state() -> {term(), reader_state()})) :: {%{String.t() => term()}, reader_state()}
  def read_map(impl, state, read_value_fun) do
    state = impl.begin_object(state)
    {map, state} = read_map_loop(impl, state, read_value_fun, %{})
    state = impl.end_object(state)
    {map, state}
  end

  defp read_array_loop(impl, state, read_elem_fun, acc) do
    {has_next, state} = impl.has_next_element?(state)
    if has_next do
      {elem, state} = read_elem_fun.(state)
      read_array_loop(impl, state, read_elem_fun, [elem | acc])
    else
      {acc, state}
    end
  end

  # ── Helper: Read map ──────────────────────────────────────────────────────

  defp read_map_loop(impl, state, read_value_fun, acc) do
    {has_next, state} = impl.has_next_field?(state)
    if has_next do
      {key, state} = impl.read_field_name(state)
      {value, state} = read_value_fun.(state)
      read_map_loop(impl, state, read_value_fun, Map.put(acc, key, value))
    else
      {acc, state}
    end
  end
end
