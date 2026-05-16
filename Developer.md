# Specodec Elixir Runtime — Developer Guide

## 1. Models

Generated model modules use `defstruct` with `@type` typespecs:

```elixir
defmodule Specodec.Generated.ModelName do
  @type t :: %__MODULE__{
    field1: String.t(),
    field2: integer(),
    field3: boolean()
  }

  defstruct [field1: "", field2: 0, field3: false]
end
```

Defaults are type-driven: `""` for string, `0` for integer, `0.0` for float, `false` for boolean, `[]` for list, `%{}` for map, `nil` for optional fields.

**KEY DIFFERENCE from PHP/Ruby**: Elixir uses a **schema-driven parser**. All model encode/decode delegates to `Specodec.Parser.encode_object/4` and `Specodec.Parser.decode_object/4` with a keyword list schema:

```elixir
# Schema format: [{wire_name, elixir_atom, type_spec}, ...]
@schema [
  {"field_name", :field_name, {:string, []}},
  {"count", :count, {:int32, []}},
  {"tags", :tags, {:array, [elem: {:string, []}]}},
]
```

The schema preserves order via keyword list (important for maps with >32 fields in Erlang/Elixir where maps become unordered). Schema entries are `{wire_name :: String.t(), elixir_atom :: atom(), type_spec :: tuple()}`.

## 2. Optional / Nullable Fields

Optional fields use `type | nil` in typespecs and `{:optional, [inner: type_spec]}` in the schema:

```elixir
@type t :: %__MODULE__{field: String.t() | nil}
@schema [{"field", :field, {:optional, [inner: {:string, []}]}}]
```

At decode time, `is_null?` is checked first; if true, `nil` is returned. At encode time, optional fields with `nil` values are skipped and not counted toward the object's field count.

Model and union types can also be optional via `required: false` in their opts:
```elixir
{:model, [module: SomeModel, required: false]}
```

## 3. Unions

Unions use **tagged tuples** with pattern matching. Each union is a module:

```elixir
defmodule Specodec.Generated.UnionName do
  @variants [
    variant_a: Specodec.Generated.VariantA,
    variant_b: Specodec.Generated.VariantB,
  ]

  def decode(impl, state) do
    # Reads discriminant, then pattern matches on variant name
    # Returns {:variant_name, decoded_value}
  end

  def encode(impl, w, {:variant_name, value}) do
    # Writes discriminant, then delegates to variant module
  end
end
```

The parser dispatches to union modules via `Specodec.Parser.decode_union_value/3` and `encode_union_value/3` (`parser.ex:212-226`). The union base type reads the discriminator, then invokes the appropriate variant's decode/encode.

## 4. Enums

Enums are modules with **atom-returning functions**:

```elixir
defmodule Specodec.Generated.EnumName do
  def member_a, do: :member_a
  def member_b, do: :member_b
end
```

The schema marks enum fields with `{:enum, [module: EnumName]}`. At read time, the string value from the wire is converted to an atom via a lookup. At write time, the atom is converted back to a string.

The `SpecReader::read_enum` callback returns a `String.t()`. The `SpecWriter::write_enum` callback writes a `String.t()`.

## 5. Ryu Float Formatting

Elixir's Ryu implementation uses **pure binary pattern matching** for bit extraction — no `pack`/`unpack` equivalents needed:

```elixir
# f32: Extract bits via binary pattern match
<<bits::32-big>> = <<f::float-32-big>>
# f64:
<<bits::64-big>> = <<d::float-64-big>>
```

The implementation is entirely **functional and recursive**: loops like decimal reduction use `defp` recursive functions (`while_cond/7`, `while_vm_tz/6`, `simple_reduce/5`) rather than imperative `while` loops.

| File | Purpose |
|------|---------|
| `ryu_math.ex` | `pow5bits/1`, `log10_pow2/1`, `log10_pow5/1`, `mul_shift_32/3`, `mul_shift_64/3` (takes `{lo, hi}` tuple), `multiple_of_power_of_5_32/2`, `multiple_of_power_of_2_32/2`, `multiple_of_power_of_5_64/2`, `multiple_of_power_of_2_64/2`, `decimal_length9/1`, `decimal_length17/1` |
| `ryu_f32.ex` | `float32_to_string/1` — entry point for f32, recursive functions for digit trimming |
| `ryu_f64.ex` | `float64_to_string/1` — entry point for f64, same recursive structure |
| `tables_f32.ex` | Precomputed lookup tables as module functions |
| `tables_f64.ex` | Precomputed lookup tables as module functions |

**`String.split_at`** is used in Ryu for splitting the digit string (safe because all Ryu digits are ASCII): `{first, rest} = String.split_at(digits, 1)`.

### 5a. NaN/Infinity Bit Pattern Handling

Elixir's binary pattern matching **cannot natively match NaN or Infinity bit patterns** (raises an error when `<<f::float-32-big>>` encounters NaN/Inf bits). Therefore the runtime includes custom `bits_to_float32/1` and `bits_to_float64/1` helpers:

```elixir
# msgpack_reader.ex:113-125
defp bits_to_float32(bits) do
  sign = (bits >>> 31) &&& 1
  exponent = (bits >>> 23) &&& 0xFF
  fraction = bits &&& 0x7FFFFF
  cond do
    exponent == 0xFF and fraction != 0 -> :nan
    exponent == 0xFF and sign == 0 -> :infinity
    exponent == 0xFF and sign == 1 -> :neg_infinity
    true -> <<f::float-32-native>> = <<bits::32-native>>; f
  end
end
```

These return atoms `:nan`, `:infinity`, `:neg_infinity` for special values. The writers accept these atoms directly and produce the appropriate bit patterns.

## 6. bytes

Binary data is represented as Elixir **`binary()`**. The `SpecReader::read_bytes` callback returns `{binary(), state}`. The `SpecWriter::write_bytes` callback receives a `binary()`.

- JSON wire: base64-encoded via `Base.encode64/1` / `Base.decode64!/1`.
- MsgPack wire: raw bin format (0xC4/0xC5/0xC6).

## 7. array / map

- Arrays: Elixir `list()` — read via `SpecReader.read_array/3`, written via `SpecWriter.write_array/4`
- Maps: Elixir `%{String.t() => term()}` — read via `SpecReader.read_map/3`, written via `SpecWriter.write_map/4`

The `SpecReader` module (`spec_reader.ex:32-73`) provides helper functions that handle the `begin_`/`has_next`/`end_` loop for both arrays and maps, taking a callback function for reading/writing individual elements.

## 8. MsgPack Reader/Writer

**MsgPackReader** (`msgpack_reader.ex`) uses Elixir's **binary pattern matching** extensively:

```elixir
defp read_string_val(<<0xD9, len::8, str::binary-size(len), rest::binary>>), do: {str, rest}
defp read_integer(<<0xCC, val::8, rest::binary>>), do: {val, rest}
```

State is `{binary, stack}` where `binary` is the remaining input and `stack` is a list of `%StackEntry{type:, count:}` structs tracking array/map nesting. The `dec_top/1` helper decrements the top counter after consuming a value.

**MsgPackWriter** (`msgpack_writer.ex`) uses an **IO list** for accumulation — prepending is O(1) with `[state | binary]`, and the final `to_bytes` calls `IO.iodata_to_binary(state)` to flatten efficiently.

Skip operations are implemented as explicit pattern-match clauses for each MsgPack tag, recursively skipping nested arrays and maps.

## 9. JSON Reader/Writer

**JSON Reader** (`json_reader.ex`):
- State is a 4-tuple: `{binary, pos, stack, first_elem_flag}` where `stack` is `[{:object, flag} | ...]` or `[{:array, flag} | ...]`.
- Uses `binary_part(s, pos, length)` — NOT `String.slice` — for byte-level substring extraction. This is a **critical fix**: `String.slice` works on grapheme clusters in Elixir and would fail on multi-byte UTF-8 sequences. `binary_part` operates on raw bytes.
- Unicode escape `\uXXXX` parsing (`json_reader.ex:207-221`):
  - Position calculation for non-surrogate: `pos + 5` (NOT `pos + 6`)
  - Position calculation for surrogate pair: `pos + 11` (NOT `pos + 12`)
  - These offsets account for the `\u` prefix (2 bytes) + 4 hex digits + 1 for the closing byte, and for surrogates: first `\u` (2) + 4 hex + second `\u` (2) + 4 hex + 1 = 13 total, returning `pos + 11` since `pos` was already at the first `\u`.
- String parsing uses IO list accumulation: `[ch | acc]` prepended, then `IO.iodata_to_binary(Enum.reverse(str))` at the end.
- `is_null?` checks if the next 4 bytes are `"null"` in the binary.
- `read_int64`/`read_uint64` check if the value is quoted first; if quoted, `parse_string` then `String.to_integer`. If unquoted, `Float.parse` then `trunc`.

**JSON Writer** (`json_writer.ex`):
- State is `{parts, first_item}` where `parts` is an IO list and `first_item` is a boolean stack.
- NaN/Infinity are handled by `is_nan_f32/1`, `is_inf_f32/1`, `is_neg_inf_f32/1` private functions that manually decode the IEEE 754 bit pattern from the float.
- Int64/uint64 are written as quoted strings: `[?\" | Integer.to_string(value), ?\"]`.

## 10. Gron Reader/Writer

**GronReader** (`gron_reader.ex`):
- State: `{lines, cursor, ctx}` where `ctx` is a list of `%{prefix: ..., type: :object | :array, index: ...}` maps.
- Lines are parsed on-the-fly with `line_path/1` splitting on `" = "`.
- Prefix-based path tracking (following the Python reference implementation): `has_next_field?` checks if the next line's path starts with `prefix<>"."` and doesn't contain further `.` or `[`.
- `unescape_chars/4` handles `\uXXXX` including surrogate pairs, using `:binary.at/2` for byte-level access.
- `read_gron_num/5` unquotes the value (strips surrounding `"`), then tries `Integer.parse` first, then `Float.parse`.

**GronWriter** (`gron_writer.ex`):
- State: `{lines, segments, nesting}` where `lines` is an IO list (reversed for O(1) prepend), `segments` is `["json", ...]`, and `nesting` is `[%{depth: n, array_index: i}, ...]`.
- Path building: `build_path/1` concatenates segments with `.` prefix (or no prefix for `[...]` index segments).
- Lines are prepended: `["#{path} = #{raw};" | lines]`. At `to_bytes`, `Enum.reverse(lines)` then `Enum.join("\n")`.
- Float32/float64 NaN/Infinity use the same bit-pattern detection helpers as the JSON writer.
- **BUG FIX HISTORY**: `is_neg_zero` was removed from Gron writer (negative zero produced incorrect path output). The `next_element` was initially buggy and was rewritten to follow Python's prefix-based tracking.

## 11. NaN / Infinity

Elixir does not provide NaN/Infinity float literals that survive binary pattern matching. The runtime uses **atoms** to represent special float values:
- `:nan` — NaN
- `:infinity` — positive infinity
- `:neg_infinity` — negative infinity

These are used as the return type from `bits_to_float32/1` and `bits_to_float64/1`, and as accepted input to `write_float32/2` and `write_float64/2` writer callbacks. The `FloatFmt` module (`float_fmt.ex`) also accepts these atoms directly.

## 12. State Management — Immutable State Passing

**CRITICAL UNIQUE FEATURE**: All state in the Elixir runtime is **immutable** and passed through function returns. Every reader callback returns `{value, new_state}` tuples. Every writer callback returns the updated IO list.

Reader state examples:
- JSON reader: `{binary, pos, stack, first_elem_stack}`
- MsgPack reader: `{binary, stack}`
- Gron reader: `{lines, cursor, ctx}`

Writer state examples:
- JSON writer: `{iodata_list, first_item_flag}`
- MsgPack writer: `iodata_list` (flat IO list)
- Gron writer: `{iodata_list, segments, nesting}`

All transformations are pure — no mutation occurs. This aligns with Elixir/Erlang's functional paradigm and process isolation guarantees.

## 13. SpecReader / SpecWriter Behaviours

**SpecReader** (`spec_reader.ex`) — an Elixir `@behaviour` with callbacks returning `{value, reader_state}` tuples:
- `begin_object/1`, `has_next_field?/1`, `read_field_name/1`, `end_object/1`
- `begin_array/1`, `has_next_element?/1`, `end_array/1`
- `read_string/1`, `read_bool/1`, `read_int32/1`, `read_int64/1`, `read_uint32/1`, `read_uint64/1`
- `read_float32/1`, `read_float64/1`
- `read_null/1` → `{:ok, state}`
- `read_bytes/1`, `read_enum/1`
- `is_null?/1` → `{boolean, state}`
- `skip/1`

Plus helper functions: `read_array/3` and `read_map/3`.

**SpecWriter** (`spec_writer.ex`) — an Elixir `@behaviour` with callbacks returning updated `writer_state`:
- All write callbacks return updated state
- `to_bytes/1` returns `binary()`
- Plus helpers: `write_array/4` and `write_map/4`

**SpecCodec** (`spec_codec.ex:35-63`): A struct `%Specodec.SpecCodec{encode: fun, decode: fun}`. `dispatch/4` and `respond/4` functions use `FormatRegistry` to match a format string to reader/writer modules.

### Schema-Driven Parser (`parser.ex`)

The `Specodec.Parser` module is the **central dispatch engine**. All generated models delegate to it:

- `decode_object/4(impl, state, schema, mod)` — passes schema keyword list and handles field iteration
- `encode_object/4(impl, w, schema, obj)` — counts required/optional fields, writes fields in schema order
- `read_typed/3(impl, state, type, opts)` — dispatches to reader callbacks based on type atom
- `write_typed/3(w, impl, val, type, opts)` — dispatches to writer callbacks based on type atom

Supported type atoms in schema: `:string`, `:bool`, `:int32`, `:int64`, `:uint32`, `:uint64`, `:float32`, `:float64`, `:bytes`, `:enum`, `:model`, `:union`, `:array`, `:map`, `:optional`.

## 14. Container Environment

Elixir uses **mise** with Erlang and Elixir together:

```bash
MISE_ERLANG_COMPILE=1 mise use erlang@29 elixir@1.19
```

Required system dependencies:
```bash
apt install libssl-dev libncurses5-dev
```

And a UTF-8 locale:
```bash
export LANG=en_US.UTF-8
```

The `mix.exs` requires `elixir ~> 1.18`. The only external `deps` dependency is `{:jason, "~> 1.4"}` for JSON-related utilities in tests. The runtime itself is self-contained.

### BUG FIX HISTORY

Several critical bugs were fixed in the Elixir runtime during development:

1. **`String.slice` → `binary_part`**: `String.slice/2` operates on Elixir grapheme clusters, not bytes. Using it for byte-level JSON parsing caused UTF-8 multi-byte character failures. Replaced with `binary_part/3` in `json_reader.ex` (extract_number) and `gron_reader.ex` (unescape_chars).

2. **`parse_escape` position off-by-one**: The `\u` handler returned `pos + 6` for non-surrogates (should be `pos + 5`: 2 for `\u` + 4 hex digits). Surrogate pairs returned `pos + 12` (should be `pos + 11`). Fixed in `json_reader.ex:218-219`.

3. **`is_neg_zero` removed from Gron writer**: The negative zero check in the Gron writer caused incorrect path tracking behavior. Removed entirely.

## Emitter

**Source:** `/home/ytr/Specodec/typespec-emitter-elixir/src/index.ts`

The TypeSpec emitter generates Elixir source files for:
- `defmodule` with `defstruct`, `@type t`, and `@schema` keyword list
- Enum modules with atom-returning functions and string↔atom lookup
- Union modules with tagged-tuple encoding and pattern-matching dispatch
- `SpecCodec` struct instances with encode/decode functions that delegate to `Specodec.Parser`
- Default struct values using the type-driven convention
- `{:optional, [inner: type_spec]}` entries in the schema for nullable fields
