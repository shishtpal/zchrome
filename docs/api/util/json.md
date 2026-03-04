# JSON Library (zlib-json)

A standalone JSON parsing, stringification, encoding, and decoding library for Zig 0.16.0-dev.

## Import

```zig
const json = @import("json");

// Or via CDP module:
const cdp = @import("cdp");
const json = cdp.json;
```

## Core Types

### Value

The JSON value type representing any JSON data:

```zig
pub const Value = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: Array,   // ArrayListUnmanaged(Value)
    object: Object, // StringArrayHashMapUnmanaged(Value)
};
```

## Parsing & Stringification

### parse

Parse a JSON string into a Value. **Caller must call `value.deinit(allocator)` when done.**

```zig
pub fn parse(allocator: Allocator, input: []const u8, options: ParseOptions) ParseError!Value

pub const ParseOptions = struct {
    max_depth: usize = 256,              // Maximum nesting depth
    allow_trailing_content: bool = false, // Allow extra content after JSON
};
```

**Example:**

```zig
var value = try json.parse(allocator, "{\"key\": 42}", .{});
defer value.deinit(allocator);
```

### stringify

Convert a Value to a JSON string. Caller owns the returned memory.

```zig
pub fn stringify(allocator: Allocator, value: Value, options: StringifyOptions) StringifyError![]const u8

pub const StringifyOptions = struct {
    indent: ?usize = null,   // null = compact, otherwise spaces per level
    sort_keys: bool = false, // Alphabetically sort object keys
};
```

**Example:**

```zig
const output = try json.stringify(allocator, value, .{ .indent = 2 });
defer allocator.free(output);
```

### writeStream

Write JSON directly to any writer (no allocation for output buffer).

```zig
pub fn writeStream(writer: std.io.AnyWriter, value: Value, options: StringifyOptions) !void
```

## Encoding & Decoding (Zig Structs <-> JSON)

### encode

Encode any Zig value to a JSON string. **Automatically converts snake_case field names to camelCase.**

```zig
pub fn encode(allocator: Allocator, value: anytype, options: EncodeOptions) EncodeError![]const u8

pub const EncodeOptions = struct {
    convert_snake_to_camel: bool = true,  // snake_case → camelCase
    skip_null_optionals: bool = true,     // Don't emit null optional fields
};
```

**Example:**

```zig
const params = .{ .frame_id = "F1", .ignore_cache = true };
const json_str = try json.encode(allocator, params, .{});
defer allocator.free(json_str);
// Result: {"frameId":"F1","ignoreCache":true}
```

### decode / decodeWithOptions

Decode a JSON Value into a typed Zig struct. **Automatically converts camelCase JSON keys to snake_case fields.** Strings are duplicated, so caller must free them.

```zig
pub fn decode(comptime T: type, value: Value, allocator: Allocator) DecodeError!T
pub fn decodeWithOptions(comptime T: type, value: Value, allocator: Allocator, options: DecodeOptions) DecodeError!T

pub const DecodeOptions = struct {
    convert_camel_to_snake: bool = true, // Look up camelCase keys for snake_case fields
};
```

**Example:**

```zig
const NavigateResult = struct {
    frame_id: []const u8,
    loader_id: ?[]const u8 = null,
    error_text: ?[]const u8 = null,
};

var parsed = try json.parse(allocator, result_json, .{});
defer parsed.deinit(allocator);

var result = try json.decode(NavigateResult, parsed, allocator);
defer allocator.free(result.frame_id);
if (result.loader_id) |l| allocator.free(l);
```

## Value Accessors

### Type Accessors

Return the value if it matches the type, or `null` otherwise:

```zig
value.asString()   // ?[]const u8
value.asBool()     // ?bool
value.asInteger()  // ?i64
value.asFloat()    // ?f64 (also converts integers)
value.asArray()    // ?[]Value
value.asObject()   // ?Object
value.isNull()     // bool
```

### Navigation

```zig
value.get("key")   // ?Value - lookup in object
value.at(index)    // ?Value - lookup in array
value.has("key")   // bool - check if key exists
```

### Error-Returning Field Extractors

Return errors instead of null for safer extraction:

```zig
value.getString("key")  // FieldError![]const u8
value.getInt("key")     // FieldError!i64
value.getFloat("key")   // FieldError!f64
value.getBool("key")    // FieldError!bool
value.getArray("key")   // FieldError![]const Value
value.getOptional(T, "key", allocator) // !?T - decode optional field

pub const FieldError = error{ MissingField, TypeMismatch };
```

**Example:**

```zig
const result = try session.sendCommand("Page.navigate", .{ .url = url });
const frame_id = try result.getString("frameId");
const loader_id = try result.getOptional([]const u8, "loaderId", allocator);
```

## Builder Helpers

Create JSON values programmatically:

```zig
json.string(allocator, "hello")  // Value{ .string = "hello" } (duplicates)
json.int(42)                     // Value{ .integer = 42 }
json.float(3.14)                 // Value{ .float = 3.14 }
json.boolean(true)               // Value{ .bool = true }
json.nil()                       // Value.null
json.emptyArray()                // Value{ .array = .{} }
json.emptyObject()               // Value{ .object = .{} }
```

## Case Conversion Utilities

```zig
// Runtime conversion (allocates)
const camel = try json.snakeToCamel(allocator, "frame_id");    // "frameId"
const snake = try json.camelToSnake(allocator, "frameId");     // "frame_id"

// Compile-time conversion (no allocation)
const camel = comptime json.comptimeSnakeToCamel("frame_id");  // "frameId"
```

## Memory Management

**Important:** Unlike `std.json`, all parsed values own their memory and must be freed:

```zig
var value = try json.parse(allocator, input, .{});
defer value.deinit(allocator);  // REQUIRED - frees all nested memory
```

For decoded structs with string fields, free each string individually:

```zig
var result = try json.decode(MyStruct, value, allocator);
defer allocator.free(result.name);
defer if (result.optional_field) |f| allocator.free(f);
```

## Error Types

```zig
// Parsing errors
pub const ParseError = error{
    UnexpectedToken, UnexpectedEndOfInput, InvalidNumber,
    InvalidString, InvalidEscape, InvalidUnicode,
    TrailingContent, MaxDepthExceeded, OutOfMemory,
};

// Decoding errors
pub const DecodeError = error{ MissingField, TypeMismatch, OutOfMemory };

// Encoding errors
pub const EncodeError = error{ OutOfMemory };

// Field extraction errors
pub const FieldError = error{ MissingField, TypeMismatch };
```

## Usage with CDP

```zig
// Send command - params automatically encoded with snake_case → camelCase
const result = try session.sendCommand("DOM.getDocument", .{ .depth = 1 });

// Parse the result
var parsed = try result.parseResult(allocator);
defer parsed.deinit(allocator);

// Extract fields using error-returning accessors
const root = parsed.get("root") orelse return error.InvalidResponse;
const node_id = try root.getInt("nodeId");
const node_name = try root.getString("nodeName");

// Handle optional fields
const children = root.getArray("children") catch null;

// Or decode into a struct
const Document = struct {
    node_id: i64,
    node_name: []const u8,
    children: ?[]const json.Value = null,
};
var doc = try json.decode(Document, root, allocator);
```

## Supported Types for Encoding

- Primitives: `bool`, integers, floats
- Strings: `[]const u8`, `[N]u8`
- Optionals: `?T` (null becomes JSON null, or skipped if `skip_null_optionals`)
- Arrays/Slices: `[]T`, `[N]T`
- Structs: field names converted to camelCase
- Enums: encoded as string of tag name
- Tagged unions: encodes the active field's value
- Pointers: dereferenced and encoded

## Special Cases

- `NaN` and `Infinity` floats are encoded as `null` (JSON spec compliance)
- Very large integers that overflow `i64` are parsed as floats
- Unicode escapes (`\uXXXX`) and surrogate pairs are fully supported
- Control characters in strings are properly escaped
