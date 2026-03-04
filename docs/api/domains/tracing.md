# Tracing Domain

The Tracing domain provides methods for recording Chrome traces, useful for performance analysis.

## Usage

```zig
const cdp = @import("cdp");

var tracing = cdp.Tracing.init(&session);
```

## Methods

### start

Start trace recording.

```zig
pub fn start(self: *Self, opts: StartOptions) !void
```

**StartOptions:**

| Field | Type | Description |
|-------|------|-------------|
| `categories` | `?[]const u8` | Trace categories (comma-separated) |
| `options` | `?[]const u8` | Trace options |
| `buffer_usage_reporting_interval` | `?f64` | Interval for buffer usage events |
| `transfer_mode` | `?[]const u8` | "ReportEvents" or "ReturnAsStream" |
| `stream_format` | `?[]const u8` | "json" or "proto" |
| `stream_compression` | `?[]const u8` | "none" or "gzip" |
| `trace_config` | `?TraceConfig` | Detailed trace configuration |

**Example:**

```zig
try tracing.start(.{
    .categories = "-*,devtools.timeline,v8.execute,blink.console",
    .transfer_mode = "ReturnAsStream",
});
```

### end

Stop trace recording.

```zig
pub fn end(self: *Self) !void
```

### getCategories

Get available trace categories.

```zig
pub fn getCategories(self: *Self, allocator: std.mem.Allocator) ![][]const u8
```

**Example:**

```zig
const categories = try tracing.getCategories(allocator);
defer {
    for (categories) |c| allocator.free(c);
    allocator.free(categories);
}

for (categories) |cat| {
    std.debug.print("Category: {s}\n", .{cat});
}
```

### requestMemoryDump

Request a memory dump during tracing.

```zig
pub fn requestMemoryDump(self: *Self, deterministic: ?bool, level_of_detail: ?[]const u8) !MemoryDumpResult
```

### recordClockSyncMarker

Record a clock sync marker for correlating traces.

```zig
pub fn recordClockSyncMarker(self: *Self, sync_id: []const u8) !void
```

## Types

### TraceConfig

```zig
pub const TraceConfig = struct {
    record_mode: ?[]const u8 = null,
    enable_sampling: ?bool = null,
    enable_systrace: ?bool = null,
    enable_argument_filter: ?bool = null,
    included_categories: ?[]const []const u8 = null,
    excluded_categories: ?[]const []const u8 = null,
    synthetic_delays: ?[]const []const u8 = null,
    memory_dump_config: ?MemoryDumpConfig = null,
};
```

### MemoryDumpResult

```zig
pub const MemoryDumpResult = struct {
    dump_guid: []const u8,
    success: bool,
};
```

## Common Trace Categories

| Category | Description |
|----------|-------------|
| `devtools.timeline` | DevTools timeline events |
| `v8.execute` | V8 script execution |
| `blink.console` | Console API calls |
| `blink.user_timing` | User timing API |
| `disabled-by-default-devtools.timeline` | Additional timeline info |
| `disabled-by-default-v8.cpu_profiler` | V8 CPU profiler |

## CLI Usage

```bash
zchrome dev trace start
zchrome dev trace stop trace.json
zchrome dev trace categories
```
