# Profiler Domain

The Profiler domain provides CPU profiling capabilities. Profiles can be loaded in Chrome DevTools.

## Usage

```zig
const cdp = @import("cdp");

var profiler = cdp.Profiler.init(&session);
```

## Methods

### enable / disable

Enable or disable the profiler.

```zig
pub fn enable(self: *Self) !void
pub fn disable(self: *Self) !void
```

### setSamplingInterval

Set the sampling interval in microseconds.

```zig
pub fn setSamplingInterval(self: *Self, interval: u32) !void
```

**Example:**

```zig
try profiler.enable();
try profiler.setSamplingInterval(100); // Sample every 100 microseconds
```

### start / stop

Start and stop CPU profiling.

```zig
pub fn start(self: *Self) !void
pub fn stop(self: *Self, allocator: std.mem.Allocator) !Profile
```

**Example:**

```zig
try profiler.enable();
try profiler.start();

// ... code to profile ...

var profile = try profiler.stop(allocator);
defer profile.deinit(allocator);

std.debug.print("Profile duration: {d}ms\n", .{
    (profile.end_time - profile.start_time) / 1000.0
});
```

### startPreciseCoverage / stopPreciseCoverage

Collect code coverage information.

```zig
pub fn startPreciseCoverage(self: *Self, opts: CoverageOptions) !f64
pub fn stopPreciseCoverage(self: *Self) !void
```

### takePreciseCoverage

Take a coverage snapshot.

```zig
pub fn takePreciseCoverage(self: *Self, allocator: std.mem.Allocator) !CoverageResult
```

### getBestEffortCoverage

Get coverage without precise coverage enabled.

```zig
pub fn getBestEffortCoverage(self: *Self, allocator: std.mem.Allocator) ![]ScriptCoverage
```

## Types

### Profile

CPU profile data, compatible with Chrome DevTools.

```zig
pub const Profile = struct {
    nodes: []ProfileNode,
    start_time: f64,
    end_time: f64,
    samples: ?[]i64 = null,
    time_deltas: ?[]i64 = null,

    pub fn deinit(self: *Profile, allocator: std.mem.Allocator) void
    pub fn toJson(self: *const Profile, allocator: std.mem.Allocator) ![]const u8
};
```

**toJson()** serializes the profile to Chrome DevTools compatible JSON format.

### ProfileNode

```zig
pub const ProfileNode = struct {
    id: i64,
    call_frame: CallFrame,
    hit_count: ?i64 = null,
    children: ?[]i64 = null,
    deopt_reason: ?[]const u8 = null,
    position_ticks: ?[]PositionTickInfo = null,
};
```

### CallFrame

```zig
pub const CallFrame = struct {
    function_name: []const u8,
    script_id: []const u8,
    url: []const u8,
    line_number: i32,
    column_number: i32,
};
```

### CoverageOptions

```zig
pub const CoverageOptions = struct {
    call_count: ?bool = null,
    detailed: ?bool = null,
    allow_triggered_updates: ?bool = null,
};
```

## Saving Profiles

```zig
var profile = try profiler.stop(allocator);
defer profile.deinit(allocator);

// Convert to Chrome DevTools format
const json = try profile.toJson(allocator);
defer allocator.free(json);

// Write to file
const file = try std.fs.cwd().createFile("profile.cpuprofile", .{});
defer file.close();
try file.writeAll(json);
```

## CLI Usage

```bash
# Start profiling
zchrome dev profiler start

# Do some work in the browser...

# Stop and save profile
zchrome dev profiler stop profile.cpuprofile

# Output:
# CPU profile saved to profile.cpuprofile
#   Nodes: 245
#   Duration: 1234.56ms
#
# Open in Chrome DevTools: Performance tab > Load profile
```

## Loading in Chrome DevTools

1. Open Chrome DevTools (F12)
2. Go to the Performance tab
3. Click the "Load profile" button (up arrow icon)
4. Select the `.cpuprofile` file
5. The profile will be displayed in the timeline view
