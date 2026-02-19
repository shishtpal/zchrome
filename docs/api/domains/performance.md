# Performance Domain

The `Performance` domain provides methods for collecting performance metrics.

## Import

```zig
const cdp = @import("cdp");
const Performance = cdp.Performance;
```

## Initialization

```zig
var session = try browser.newPage();
var performance = Performance.init(session);
try performance.enable();
```

## Methods

### enable

Enable performance metrics collection.

```zig
pub fn enable(self: *Performance) !void
```

### disable

Disable performance metrics collection.

```zig
pub fn disable(self: *Performance) !void
```

### getMetrics

Get current performance metrics.

```zig
pub fn getMetrics(self: *Performance, allocator: Allocator) ![]Metric
```

**Returns:** Slice of metrics (caller must free)

**Example:**

```zig
const metrics = try performance.getMetrics(allocator);
defer {
    for (metrics) |*m| m.deinit(allocator);
    allocator.free(metrics);
}

for (metrics) |m| {
    std.debug.print("{s}: {d}\n", .{m.name, m.value});
}
```

## Types

### Metric

```zig
pub const Metric = struct {
    name: []const u8,
    value: f64,

    pub fn deinit(self: *Metric, allocator: Allocator) void;
};
```

## Available Metrics

| Metric | Description |
|--------|-------------|
| `Timestamp` | Current timestamp |
| `Documents` | Number of documents |
| `Frames` | Number of frames |
| `JSEventListeners` | JS event listener count |
| `Nodes` | DOM node count |
| `LayoutCount` | Layout operations |
| `RecalcStyleCount` | Style recalculations |
| `LayoutDuration` | Layout time (seconds) |
| `RecalcStyleDuration` | Style recalc time |
| `ScriptDuration` | Script execution time |
| `TaskDuration` | Task execution time |
| `JSHeapUsedSize` | JS heap used (bytes) |
| `JSHeapTotalSize` | JS heap total (bytes) |

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
    var performance = cdp.Performance.init(session);
    
    try page.enable();
    try performance.enable();

    _ = try page.navigate(allocator, "https://example.com");

    // Wait for load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Get metrics
    const metrics = try performance.getMetrics(allocator);
    defer {
        for (metrics) |*m| m.deinit(allocator);
        allocator.free(metrics);
    }

    std.debug.print("Performance Metrics:\n", .{});
    for (metrics) |m| {
        // Format based on metric type
        if (std.mem.endsWith(u8, m.name, "Duration")) {
            std.debug.print("  {s}: {d:.3}s\n", .{m.name, m.value});
        } else if (std.mem.endsWith(u8, m.name, "Size")) {
            std.debug.print("  {s}: {d:.0} bytes\n", .{m.name, m.value});
        } else {
            std.debug.print("  {s}: {d:.0}\n", .{m.name, m.value});
        }
    }
}
```

## Performance Analysis

### Memory Usage

```zig
const metrics = try performance.getMetrics(allocator);
defer { /* cleanup */ };

for (metrics) |m| {
    if (std.mem.eql(u8, m.name, "JSHeapUsedSize")) {
        const mb = m.value / 1024 / 1024;
        std.debug.print("JS Heap: {d:.2} MB\n", .{mb});
    }
}
```

### Rendering Performance

```zig
for (metrics) |m| {
    if (std.mem.eql(u8, m.name, "LayoutDuration")) {
        std.debug.print("Layout: {d:.3}s\n", .{m.value});
    }
    if (std.mem.eql(u8, m.name, "RecalcStyleDuration")) {
        std.debug.print("Style: {d:.3}s\n", .{m.value});
    }
}
```

### Script Performance

```zig
for (metrics) |m| {
    if (std.mem.eql(u8, m.name, "ScriptDuration")) {
        std.debug.print("Script execution: {d:.3}s\n", .{m.value});
    }
    if (std.mem.eql(u8, m.name, "TaskDuration")) {
        std.debug.print("Task execution: {d:.3}s\n", .{m.value});
    }
}
```
