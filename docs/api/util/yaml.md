# YAML Utilities

Helper functions for simple YAML serialization of flat string-to-string maps.

## Import

```zig
const cdp = @import("cdp");
const yaml = cdp.yaml;
```

## Functions

### isYamlPath

Check if a file path has a YAML extension (`.yaml` or `.yml`).

```zig
pub fn isYamlPath(path: []const u8) bool
```

**Example:**

```zig
if (cdp.yaml.isYamlPath("data.yaml")) {
    // Handle YAML format
}
```

### jsonToYaml

Convert a JSON object string to simple YAML format.

```zig
pub fn jsonToYaml(allocator: std.mem.Allocator, json_str: []const u8) ![]u8
```

Converts a JSON object like `{"key1": "value1", "key2": "value2"}` to YAML:

```yaml
key1: value1
key2: value2
```

**Example:**

```zig
const json_str = "{\"name\": \"Alice\", \"city\": \"NYC\"}";
const yaml_str = try cdp.yaml.jsonToYaml(allocator, json_str);
defer allocator.free(yaml_str);
// yaml_str = "name: Alice\ncity: NYC\n"
```

**Note:** This function only handles flat string-to-string maps. Nested objects
and non-string values are not supported.

### yamlToJson

Parse simple YAML key-value lines into a JSON object string.

```zig
pub fn yamlToJson(allocator: std.mem.Allocator, yaml: []const u8) ![]const u8
```

Converts YAML like:

```yaml
name: Alice
city: NYC
```

To JSON: `{"name":"Alice","city":"NYC"}`

**Example:**

```zig
const yaml_content = "name: Alice\ncity: NYC\n";
const json_str = try cdp.yaml.yamlToJson(allocator, yaml_content);
defer allocator.free(json_str);
// json_str = "{\"name\":\"Alice\",\"city\":\"NYC\"}"
```

**Note:** This function only handles simple `key: value` lines. Comments (lines
starting with `#`) and empty lines are ignored.

## Usage with Storage Export/Import

The YAML utilities are designed for exporting and importing web storage data:

```zig
// Export localStorage to YAML
const js = "JSON.stringify(Object.fromEntries(Object.keys(localStorage).map(k => [k, localStorage.getItem(k)])))";
const json_result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
const yaml_output = try cdp.yaml.jsonToYaml(allocator, json_result.asString().?);

// Import YAML into localStorage
const yaml_content = try readFile("storage.yaml");
const json_str = try cdp.yaml.yamlToJson(allocator, yaml_content);
// Parse JSON and set localStorage entries...
```

## Limitations

- Only flat string-to-string maps are supported
- No support for nested objects, arrays, or typed values
- YAML comments and complex structures are not parsed
- Designed specifically for localStorage/sessionStorage serialization
