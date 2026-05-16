#!/usr/bin/env elixir
# Elixir roundtrip test

# Load JASON dependency (installed by mix)
jason_ebin = "_build/dev/lib/jason/ebin"
if File.dir?(jason_ebin) do
  Code.append_path(jason_ebin)
end

# ── Helpers ──
scalar_read = fn type ->
  case type do
    "int32" -> :read_int32; "int64" -> :read_int64; "uint32" -> :read_uint32
    "uint64" -> :read_uint64; "float32" -> :read_float32; "float64" -> :read_float64
    "string" -> :read_string; "bytes" -> :read_bytes; "bool" -> :read_bool
    _ -> :read_int32
  end
end

scalar_write = fn type ->
  case type do
    "int32" -> :write_int32; "int64" -> :write_int64; "uint32" -> :write_uint32
    "uint64" -> :write_uint64; "float32" -> :write_float32; "float64" -> :write_float64
    "string" -> :write_string; "bytes" -> :write_bytes; "bool" -> :write_bool
    _ -> :write_int32
  end
end

test_format = fn mod, vec, out, model, out_ext, vec_ext, reader_mod, writer_mod, p, f ->
  vec_path = Path.join(vec, "#{model}.#{vec_ext}")
  out_path = Path.join(out, "#{model}.#{out_ext}")
  try do
    expected = File.read!(vec_path)
    reader = reader_mod.new(expected)
    {obj, _r} = mod.decode(reader_mod, reader)
    writer = writer_mod.new()
    w = mod.encode(writer_mod, writer, obj)
    actual = writer_mod.to_bytes(w)
    File.write!(out_path, actual)
    if actual == expected, do: {p + 1, f}, else: (IO.puts(:stderr, "FAIL #{model}.#{out_ext}"); {p, f + 1})
  rescue
    e -> IO.puts(:stderr, "FAIL #{model}.#{out_ext}: #{inspect(e)}"); {p, f + 1}
  end
end

# Compile runtime in order
compile_order = [
  "lib/specodec/spec_reader.ex", "lib/specodec/spec_writer.ex",
  "lib/specodec/parser.ex",
  "lib/specodec/tables_f32.ex", "lib/specodec/tables_f64.ex",
  "lib/specodec/ryu_math.ex", "lib/specodec/ryu_f32.ex", "lib/specodec/ryu_f64.ex",
  "lib/specodec/float_fmt.ex",
  "lib/specodec/msgpack_reader.ex", "lib/specodec/msgpack_writer.ex",
  "lib/specodec/json_reader.ex", "lib/specodec/json_writer.ex",
  "lib/specodec/gron_reader.ex", "lib/specodec/gron_writer.ex",
  "lib/specodec/spec_codec.ex",
]
Enum.each(compile_order, &Code.compile_file/1)

# Compile generated files
gen_dir = "tests/interop/src/generated"
Path.wildcard(Path.join(gen_dir, "*.ex")) |> Enum.sort() |> Enum.each(&Code.compile_file/1)

# Read manifest
vec = System.get_env("VEC_DIR")
out = System.get_env("OUT_DIR")
{:ok, json} = File.read(Path.join(vec, "manifest.json"))
manifest = Jason.decode!(json)
models = (manifest["testModels"] || []) ++ (manifest["testUnions"] || [])
scalars = manifest["scalars"] || %{}
test_unions = MapSet.new(manifest["testUnions"] || [])

File.mkdir_p!(out)
File.mkdir_p!(Path.join(out, "scalars"))

alias Specodec.{MsgPackReader, MsgPackWriter, JsonReader, JsonWriter, GronReader, GronWriter}

# ── Scalars ──
IO.puts(:stderr, "Testing #{map_size(scalars)} scalars...")
{sp, sf} = Enum.reduce(scalars, {0, 0}, fn {name, info}, {p, f} ->
  try do
    expected = File.read!(Path.join(vec, "scalars/#{name}.mp"))
    reader = MsgPackReader.new(expected)
    {val, _r} = apply(MsgPackReader, scalar_read.(info["type"]), [reader])
    writer = MsgPackWriter.new()
    w = apply(MsgPackWriter, scalar_write.(info["type"]), [writer, val])
    actual = MsgPackWriter.to_bytes(w)
    File.write!(Path.join(out, "scalars/#{name}.mp"), actual)
    if actual == expected, do: {p + 1, f}, else: (IO.puts(:stderr, "FAIL scalar #{name}"); {p, f + 1})
  rescue
    e -> IO.puts(:stderr, "FAIL scalar #{name}: #{inspect(e)}"); {p, f + 1}
  end
end)

# ── Models ──
IO.puts(:stderr, "Testing #{length(models)} models...")
{mp, mf} = Enum.reduce(Enum.with_index(models), {0, 0}, fn {model, i}, {p, f} ->
  codec_name = if MapSet.member?(test_unions, model) do
    String.replace(model, ~r/_[^_]+$/, "")
  else
    model
  end
  mod = Module.concat(Specodec.Generated, String.to_atom(codec_name))

  # MsgPack
  {p, f} = test_format.(mod, vec, out, model, "msgpack", "msgpack", MsgPackReader, MsgPackWriter, p, f)
  # JSON
  {p, f} = test_format.(mod, vec, out, model, "json", "json", JsonReader, JsonWriter, p, f)
  # Unformatted JSON
  {p, f} = test_format.(mod, vec, out, model, "unformatted.json", "json", JsonReader, JsonWriter, p, f)
  # Gron
  {p, f} = test_format.(mod, vec, out, model, "gron", "gron", GronReader, GronWriter, p, f)

  if rem(i + 1, 50) == 0, do: IO.puts(:stderr, "  #{i + 1}/#{length(models)} models...")
  {p, f}
end)

total_pass = sp + mp
total_fail = sf + mf
IO.puts("emit-elixir: #{total_pass} passed, #{total_fail} failed")
if total_fail > 0, do: System.halt(1)
