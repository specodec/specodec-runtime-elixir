defmodule Specodec.SpecWriter do
  @moduledoc """
  Behaviour for struct-to-binary writers (MsgPack, JSON, Gron).

  Each writer implementation is a module that implements these callbacks.
  The writer state is passed as the first argument and returned as the second
  element of the tuple. Use `state` to accumulate the output bytes.
  """

  @type writer_state :: term()

  @callback write_string(writer_state(), String.t()) :: writer_state()
  @callback write_bool(writer_state(), boolean()) :: writer_state()
  @callback write_int32(writer_state(), integer()) :: writer_state()
  @callback write_int64(writer_state(), integer()) :: writer_state()
  @callback write_uint32(writer_state(), integer()) :: writer_state()
  @callback write_uint64(writer_state(), integer()) :: writer_state()
  @callback write_float32(writer_state(), float()) :: writer_state()
  @callback write_float64(writer_state(), float()) :: writer_state()
  @callback write_null(writer_state()) :: writer_state()
  @callback write_bytes(writer_state(), binary()) :: writer_state()
  @callback write_enum(writer_state(), String.t()) :: writer_state()
  @callback begin_object(writer_state(), integer()) :: writer_state()
  @callback write_field(writer_state(), String.t()) :: writer_state()
  @callback end_object(writer_state()) :: writer_state()
  @callback begin_array(writer_state(), integer()) :: writer_state()
  @callback next_element(writer_state()) :: writer_state()
  @callback end_array(writer_state()) :: writer_state()
  @callback to_bytes(writer_state()) :: binary()

  # ── Helper: Write array ───────────────────────────────────────────────────

  @doc "Write a list by calling the element write function for each item"
  @spec write_array(module(), writer_state(), list(term()), (writer_state(), term() -> writer_state())) :: writer_state()
  def write_array(impl, state, list, write_elem_fun) do
    state = impl.begin_array(state, length(list))
    state = Enum.reduce(list, state, fn item, st ->
      st = impl.next_element(st)
      write_elem_fun.(st, item)
    end)
    impl.end_array(state)
  end

  # ── Helper: Write map ─────────────────────────────────────────────────────

  @doc "Write a map by calling the value write function for each key-value pair"
  @spec write_map(module(), writer_state(), %{String.t() => term()}, (writer_state(), term() -> writer_state())) :: writer_state()
  def write_map(impl, state, map, write_value_fun) do
    state = impl.begin_object(state, map_size(map))
    state = Enum.reduce(map, state, fn {key, value}, st ->
      st = impl.write_field(st, key)
      write_value_fun.(st, value)
    end)
    impl.end_object(state)
  end
end
