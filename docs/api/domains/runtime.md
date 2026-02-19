# Runtime Domain

The `Runtime` domain provides methods for JavaScript execution and object inspection.

## Import

```zig
const cdp = @import("cdp");
const Runtime = cdp.Runtime;
```

## Initialization

```zig
var session = try browser.newPage();
var runtime = Runtime.init(session);
try runtime.enable();
```

## Methods

### enable / disable

Enable or disable the Runtime domain.

```zig
pub fn enable(self: *Runtime) !void
pub fn disable(self: *Runtime) !void
```

### evaluate

Evaluate a JavaScript expression.

```zig
pub fn evaluate(
    self: *Runtime,
    allocator: Allocator,
    expression: []const u8,
    options: EvaluateOptions,
) !EvaluateResult
```

**Options:**

| Field | Type | Description |
|-------|------|-------------|
| `return_by_value` | `?bool` | Return primitive value |
| `await_promise` | `?bool` | Wait for promise resolution |
| `generate_preview` | `?bool` | Generate object preview |
| `user_gesture` | `?bool` | Emulate user gesture |
| `include_command_line_api` | `?bool` | Include console API |

**Returns:** `EvaluateResult` (caller must deinit)

**Example:**

```zig
var result = try runtime.evaluate(allocator, "1 + 2", .{
    .return_by_value = true,
});
defer result.deinit(allocator);

if (result.value) |v| {
    switch (v) {
        .integer => |i| std.debug.print("Result: {}\n", .{i}),
        else => {},
    }
}
```

### evaluateAs

Evaluate and return as a specific type.

```zig
pub fn evaluateAs(self: *Runtime, comptime T: type, expression: []const u8) !T
```

**Supported types:** `[]const u8`, `i64`, `f64`, `bool`

**Example:**

```zig
const title = try runtime.evaluateAs([]const u8, "document.title");
const count = try runtime.evaluateAs(i64, "document.links.length");
const visible = try runtime.evaluateAs(bool, "document.hidden === false");
```

### callFunctionOn

Call a function on a remote object.

```zig
pub fn callFunctionOn(
    self: *Runtime,
    allocator: Allocator,
    function_declaration: []const u8,
    object_id: []const u8,
    arguments: ?[]const CallArgument,
) !EvaluateResult
```

**Example:**

```zig
var result = try runtime.callFunctionOn(
    allocator,
    "function() { return this.innerText; }",
    object_id,
    null,
);
defer result.deinit(allocator);
```

### getProperties

Get properties of a remote object.

```zig
pub fn getProperties(
    self: *Runtime,
    allocator: Allocator,
    object_id: []const u8,
    own_properties: bool,
) ![]PropertyDescriptor
```

### releaseObject

Release a remote object.

```zig
pub fn releaseObject(self: *Runtime, object_id: []const u8) !void
```

### releaseObjectGroup

Release all objects in a group.

```zig
pub fn releaseObjectGroup(self: *Runtime, object_group: []const u8) !void
```

## Types

### EvaluateResult

```zig
pub const EvaluateResult = struct {
    type: []const u8,           // "undefined", "string", "number", etc.
    value: ?std.json.Value = null,
    object_id: ?[]const u8 = null,
    description: ?[]const u8 = null,
    exception_details: ?ExceptionDetails = null,

    pub fn deinit(self: *EvaluateResult, allocator: Allocator) void;
};
```

### RemoteObject

```zig
pub const RemoteObject = struct {
    type: []const u8,
    subtype: ?[]const u8 = null,
    class_name: ?[]const u8 = null,
    value: ?std.json.Value = null,
    object_id: ?[]const u8 = null,
    description: ?[]const u8 = null,
};
```

### ExceptionDetails

```zig
pub const ExceptionDetails = struct {
    text: []const u8,
    line_number: i64,
    column_number: i64,
    script_id: ?[]const u8 = null,
    url: ?[]const u8 = null,
    stack_trace: ?[]const u8 = null,
};
```

## JavaScript Patterns

### Get Element Text

```zig
const text = try runtime.evaluateAs(
    []const u8,
    "document.querySelector('h1').innerText",
);
```

### Get Element Count

```zig
const count = try runtime.evaluateAs(
    i64,
    "document.querySelectorAll('a').length",
);
```

### Check Element Existence

```zig
const exists = try runtime.evaluateAs(
    bool,
    "document.querySelector('#login-form') !== null",
);
```

### Get JSON Data

```zig
var result = try runtime.evaluate(allocator,
    "JSON.parse(document.querySelector('script[type=\"application/json\"]').textContent)",
    .{ .return_by_value = true },
);
defer result.deinit(allocator);
```

### Execute Complex Script

```zig
const script =
    \\(function() {
    \\    const links = Array.from(document.querySelectorAll('a[href]'));
    \\    return links.map(a => ({
    \\        text: a.innerText.trim(),
    \\        href: a.href
    \\    }));
    \\})()
;

var result = try runtime.evaluate(allocator, script, .{
    .return_by_value = true,
});
defer result.deinit(allocator);
```

## Complete Example

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var browser = try cdp.Browser.launch(.{
        .headless = .new,
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    var runtime = cdp.Runtime.init(session);
    
    try page.enable();
    try runtime.enable();

    _ = try page.navigate(allocator, "https://example.com");
    
    // Wait for load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Get page info
    const title = try runtime.evaluateAs([]const u8, "document.title");
    const url = try runtime.evaluateAs([]const u8, "location.href");
    const link_count = try runtime.evaluateAs(i64, "document.links.length");

    std.debug.print("Title: {s}\n", .{title});
    std.debug.print("URL: {s}\n", .{url});
    std.debug.print("Links: {}\n", .{link_count});

    // Complex evaluation
    var result = try runtime.evaluate(allocator,
        \\{
        \\    title: document.title,
        \\    h1: document.querySelector('h1')?.innerText,
        \\    paragraphs: document.querySelectorAll('p').length
        \\}
    , .{ .return_by_value = true });
    defer result.deinit(allocator);
}
```
