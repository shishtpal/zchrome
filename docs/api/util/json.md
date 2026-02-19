# JSON Utilities

Helper functions for working with JSON in CDP responses.

## Import

```zig
const cdp = @import("cdp");
const json = cdp.json;
```

## Functions

### getString

Extract a string field from a JSON object.

```zig
pub fn getString(obj: std.json.Value, key: []const u8) ![]const u8
```

**Example:**

```zig
const result = try session.sendCommand("Page.navigate", .{ .url = url });
const frame_id = try json.getString(result, "frameId");
```

### getInt

Extract an integer field.

```zig
pub fn getInt(obj: std.json.Value, key: []const u8) !i64
```

**Example:**

```zig
const node_id = try json.getInt(result, "nodeId");
```

### getFloat

Extract a float field.

```zig
pub fn getFloat(obj: std.json.Value, key: []const u8) !f64
```

### getBool

Extract a boolean field.

```zig
pub fn getBool(obj: std.json.Value, key: []const u8) !bool
```

### getArray

Extract an array field.

```zig
pub fn getArray(obj: std.json.Value, key: []const u8) ![]std.json.Value
```

**Example:**

```zig
const items = try json.getArray(result, "nodeIds");
for (items) |item| {
    // Process each item
}
```

### getObject

Extract a nested object field.

```zig
pub fn getObject(obj: std.json.Value, key: []const u8) !std.json.Value
```

## Error Handling

All functions return errors if:
- The key doesn't exist
- The value has the wrong type

```zig
const value = json.getString(obj, "missingKey") catch |err| {
    // err is error.MissingField or error.TypeMismatch
};
```

## Usage with CDP

```zig
// Send command
const result = try session.sendCommand("DOM.getDocument", .{ .depth = 1 });

// Extract fields
const root = try json.getObject(result, "root");
const node_id = try json.getInt(root, "nodeId");
const node_name = try json.getString(root, "nodeName");
const children = json.getArray(root, "children") catch null;
```

## Optional Fields

For optional fields, use catch to provide defaults:

```zig
const optional_value = json.getString(obj, "optionalField") catch "";
const optional_int = json.getInt(obj, "count") catch 0;
```

Or check for null:

```zig
if (obj.object.get("optionalField")) |value| {
    const str = value.string;
} else {
    // Field not present
}
```
