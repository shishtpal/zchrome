# Memory Management

zchrome follows Zig's explicit memory management philosophy. Every allocation goes through a user-provided allocator.

## Core Principles

1. **No hidden allocations** - All allocations require an allocator
2. **Caller owns returned memory** - You allocate, you free
3. **Structs with `deinit`** - Complex types provide cleanup methods
4. **`defer` for cleanup** - Use defer to ensure cleanup

## Allocator Passing

### Launch Options

```zig
var browser = try cdp.Browser.launch(.{
    .allocator = allocator,  // Required
    .io = init.io,
});
```

### Method Calls

Methods that allocate take an allocator parameter:

```zig
// Allocates result struct
var result = try page.navigate(allocator, url);
defer result.deinit(allocator);

// Allocates string
const html = try dom.getOuterHTML(allocator, node_id);
defer allocator.free(html);

// Allocates slice
const cookies = try storage.getCookies(allocator, null);
defer {
    for (cookies) |*c| c.deinit(allocator);
    allocator.free(cookies);
}
```

## Cleanup Patterns

### Simple Values

```zig
const screenshot = try page.captureScreenshot(allocator, .{ .format = .png });
defer allocator.free(screenshot);
```

### Structs with deinit

```zig
var result = try page.navigate(allocator, url);
defer result.deinit(allocator);

var doc = try dom.getDocument(allocator, 1);
defer doc.deinit(allocator);

var version = try browser.version();
defer version.deinit(allocator);
```

### Slices of Structs

```zig
const targets = try target.getTargets(allocator);
defer {
    for (targets) |*t| {
        t.deinit(allocator);
    }
    allocator.free(targets);
}
```

### Error Handling with defer

```zig
var result = try page.navigate(allocator, url);
errdefer result.deinit(allocator);

// If this fails, result is cleaned up
try someOtherOperation();

// Manual cleanup on success path
result.deinit(allocator);
```

## Struct Definitions

### NavigateResult

```zig
pub const NavigateResult = struct {
    frame_id: []const u8,
    loader_id: ?[]const u8 = null,
    error_text: ?[]const u8 = null,

    pub fn deinit(self: *NavigateResult, allocator: Allocator) void {
        allocator.free(self.frame_id);
        if (self.loader_id) |id| allocator.free(id);
        if (self.error_text) |t| allocator.free(t);
    }
};
```

### Node

```zig
pub const Node = struct {
    node_id: i64,
    node_type: i64,
    node_name: []const u8,
    node_value: []const u8,
    children: ?[]Node = null,

    pub fn deinit(self: *Node, allocator: Allocator) void {
        allocator.free(self.node_name);
        allocator.free(self.node_value);
        if (self.children) |children| {
            for (children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children);
        }
    }
};
```

### BrowserVersion

```zig
pub const BrowserVersion = struct {
    protocol_version: []const u8,
    product: []const u8,
    revision: []const u8,
    user_agent: []const u8,
    js_version: []const u8,

    pub fn deinit(self: *BrowserVersion, allocator: Allocator) void {
        allocator.free(self.protocol_version);
        allocator.free(self.product);
        allocator.free(self.revision);
        allocator.free(self.user_agent);
        allocator.free(self.js_version);
    }
};
```

## Allocator Recommendations

### GeneralPurposeAllocator

Use for long-running applications:

```zig
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    // Use allocator...
}
```

### ArenaAllocator

Use for batch operations with single cleanup:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

const allocator = arena.allocator();

// All allocations freed at once when arena.deinit() is called
for (urls) |url| {
    const result = try page.navigate(allocator, url);
    // Don't need individual deinit - arena handles it
}
```

### FixedBufferAllocator

Use for constrained environments:

```zig
var buffer: [1024 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();
```

## Memory Leak Detection

Use GPA's leak detection in debug builds:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("Memory leak detected!\n", .{});
    }
}

const allocator = gpa.allocator();
```

## Best Practices

1. **Always pair allocation with defer**
   ```zig
   const data = try allocate();
   defer cleanup(data);
   ```

2. **Use errdefer for error paths**
   ```zig
   const data = try allocate();
   errdefer cleanup(data);
   try mightFail();
   ```

3. **Check for null optionals before freeing**
   ```zig
   if (self.optional_field) |field| {
       allocator.free(field);
   }
   ```

4. **Free slices of structs correctly**
   ```zig
   for (items) |*item| {
       item.deinit(allocator);
   }
   allocator.free(items);
   ```

5. **Use arena allocators for batch operations**
   ```zig
   var arena = std.heap.ArenaAllocator.init(allocator);
   defer arena.deinit();
   // All temp allocations cleaned up at once
   ```
