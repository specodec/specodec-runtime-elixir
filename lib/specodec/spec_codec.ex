defmodule Specodec.FormatEntry do
  defstruct [:name, :writer_module, :reader_module]
end

defmodule Specodec.FormatRegistry do
  defstruct entries: []

  def new do
    %Specodec.FormatRegistry{
      entries: [
        %Specodec.FormatEntry{
          name: "json",
          writer_module: Specodec.JsonWriter,
          reader_module: Specodec.JsonReader
        },
        %Specodec.FormatEntry{
          name: "msgpack",
          writer_module: Specodec.MsgPackWriter,
          reader_module: Specodec.MsgPackReader
        },
        %Specodec.FormatEntry{
          name: "gron",
          writer_module: Specodec.GronWriter,
          reader_module: Specodec.GronReader
        }
      ]
    }
  end

  def match(%Specodec.FormatRegistry{entries: entries}, format) do
    Enum.find(entries, hd(entries), fn e -> e.name == format end)
  end
end

defmodule Specodec.SpecCodec do
  @moduledoc """
  A codec pairs encode and decode functions for a type.
  encode: (impl_module, writer_state, value) -> writer_state
  decode: (impl_module, reader_state) -> {value, reader_state}
  """

  defstruct [:encode, :decode]

  @type t :: %__MODULE__{
    encode: (module(), Specodec.SpecWriter.writer_state(), term() -> Specodec.SpecWriter.writer_state()),
    decode: (module(), Specodec.SpecReader.reader_state() -> {term(), Specodec.SpecReader.reader_state()})
  }

  @doc "Dispatch: decode bytes using the given format"
  def dispatch(%Specodec.SpecCodec{decode: decode}, body, format, registry \\ Specodec.FormatRegistry.new()) do
    entry = Specodec.FormatRegistry.match(registry, format)
    {result, _state} = entry.reader_module.new(body) |> decode.()
    result
  end

  @doc "Respond: encode a value to bytes using the given format"
  def respond(%Specodec.SpecCodec{encode: encode}, obj, format, registry \\ Specodec.FormatRegistry.new()) do
    entry = Specodec.FormatRegistry.match(registry, format)
    writer_state = entry.writer_module.new()
    final_state = encode.(writer_state, obj)
    {entry.writer_module.to_bytes(final_state), entry.name}
  end
end
