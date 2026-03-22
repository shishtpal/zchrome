# Debugger Domain

The `Debugger` domain provides methods for JavaScript debugging including breakpoints, stepping, and inspecting execution state.

## Import

```zig
const cdp = @import("cdp");
const Debugger = cdp.Debugger;
```

## Initialization

```zig
var session = try browser.newPage();
var debugger_domain = Debugger.init(session);
_ = try debugger_domain.enable();
```

## Methods

### enable

Enable the debugger domain. Returns the debugger protocol version.

```zig
pub fn enable(self: *Debugger) !i64
```

**Example:**
```zig
var dbg = cdp.Debugger.init(session);
const version = try dbg.enable();
std.debug.print("Debugger version: {}\n", .{version});
```

### disable

Disable the debugger domain.

```zig
pub fn disable(self: *Debugger) !void
```

### pause

Pause JavaScript execution immediately.

```zig
pub fn pause(self: *Debugger) !void
```

### resume

Resume JavaScript execution after being paused.

```zig
pub fn @"resume"(self: *Debugger) !void
```

::: tip
The method is named `@"resume"` because `resume` is a reserved keyword in Zig.
:::

### stepOver

Step over the next statement (doesn't enter function calls).

```zig
pub fn stepOver(self: *Debugger) !void
```

### stepInto

Step into a function call.

```zig
pub fn stepInto(self: *Debugger) !void
```

### stepOut

Step out of the current function.

```zig
pub fn stepOut(self: *Debugger) !void
```

### setBreakpointByUrl

Set a breakpoint by URL. Can match multiple scripts.

```zig
pub fn setBreakpointByUrl(
    self: *Debugger,
    allocator: Allocator,
    line_number: i64,
    url: ?[]const u8,
    url_regex: ?[]const u8,
    script_hash: ?[]const u8,
    column_number: ?i64,
    condition: ?[]const u8,
) !BreakpointResult
```

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| `line_number` | Line number (0-based internally, but typically 1-based in source) |
| `url` | Script URL to match |
| `url_regex` | Regex pattern to match URLs |
| `script_hash` | Script content hash |
| `column_number` | Column number for the breakpoint |
| `condition` | JavaScript expression - breakpoint only triggers when true |

**Returns:**
```zig
pub const BreakpointResult = struct {
    breakpoint_id: []const u8,
    locations: []Location,
};
```

**Example:**
```zig
var dbg = cdp.Debugger.init(session);
_ = try dbg.enable();

const result = try dbg.setBreakpointByUrl(
    allocator,
    10,                              // line 10
    "http://localhost:9000/app.js",  // url
    null,                            // url_regex
    null,                            // script_hash
    null,                            // column_number
    "count > 5",                     // condition
);
defer {
    allocator.free(result.breakpoint_id);
    for (result.locations) |*loc| loc.deinit(allocator);
    allocator.free(result.locations);
}

std.debug.print("Breakpoint ID: {s}\n", .{result.breakpoint_id});
```

### setBreakpoint

Set a breakpoint at a specific location (requires script ID).

```zig
pub fn setBreakpoint(
    self: *Debugger,
    allocator: Allocator,
    location: Location,
    condition: ?[]const u8,
) !struct { breakpoint_id: BreakpointId, actual_location: Location }
```

### removeBreakpoint

Remove a breakpoint by its ID.

```zig
pub fn removeBreakpoint(self: *Debugger, breakpoint_id: []const u8) !void
```

**Example:**
```zig
try dbg.removeBreakpoint("1:10:0:http://localhost:9000/app.js");
```

### setPauseOnExceptions

Configure when to pause on exceptions.

```zig
pub fn setPauseOnExceptions(self: *Debugger, state: PauseOnExceptionsState) !void
```

**Example:**
```zig
var dbg = cdp.Debugger.init(session);
_ = try dbg.enable();
try dbg.setPauseOnExceptions(.uncaught);
```

### getScriptSource

Get the source code of a script by its ID.

```zig
pub fn getScriptSource(
    self: *Debugger,
    allocator: Allocator,
    script_id: []const u8,
) ![]const u8
```

### setBreakpointsActive

Enable or disable all breakpoints globally.

```zig
pub fn setBreakpointsActive(self: *Debugger, active: bool) !void
```

### continueToLocation

Continue execution until reaching a specific location.

```zig
pub fn continueToLocation(
    self: *Debugger,
    location: Location,
    target_call_frames: ?[]const u8,
) !void
```

### setAsyncCallStackDepth

Set the depth of async call stacks to capture.

```zig
pub fn setAsyncCallStackDepth(self: *Debugger, max_depth: i64) !void
```

### setBlackboxPatterns

Set URL patterns for scripts to skip during debugging.

```zig
pub fn setBlackboxPatterns(self: *Debugger, patterns: []const []const u8) !void
```

**Example:**
```zig
// Skip node_modules and vendor scripts
try dbg.setBlackboxPatterns(&.{
    ".*node_modules.*",
    ".*vendor.*",
});
```

## Types

### Location

```zig
pub const Location = struct {
    script_id: []const u8,
    line_number: i64,
    column_number: ?i64 = null,

    pub fn deinit(self: *Location, allocator: Allocator) void;
};
```

### PauseOnExceptionsState

```zig
pub const PauseOnExceptionsState = enum {
    none,      // Don't pause on exceptions
    uncaught,  // Pause on uncaught exceptions only
    all,       // Pause on all exceptions
};
```

### PausedReason

```zig
pub const PausedReason = enum {
    ambiguous,
    assert,
    csp_violation,
    debug_command,
    dom,
    event_listener,
    exception,
    instrumentation,
    oom,
    other,
    promise_rejection,
    xhr,
    step,
};
```

### ScopeType

```zig
pub const ScopeType = enum {
    global,
    local,
    with,
    closure,
    catch_scope,
    block,
    script,
    eval,
    module,
    wasm_expression_stack,
};
```

## Events

The debugger domain emits these events (received via CDP event handling):

| Event | Description |
|-------|-------------|
| `paused` | Execution paused (breakpoint, exception, etc.) |
| `resumed` | Execution resumed |
| `scriptParsed` | A script was parsed |
| `breakpointResolved` | A breakpoint was resolved to a location |

## Complete Example

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn debugSession(session: *cdp.Session, allocator: std.mem.Allocator) !void {
    var dbg = cdp.Debugger.init(session);
    
    // Enable the debugger
    _ = try dbg.enable();
    
    // Pause on uncaught exceptions
    try dbg.setPauseOnExceptions(.uncaught);
    
    // Set a conditional breakpoint
    const bp = try dbg.setBreakpointByUrl(
        allocator,
        25,                               // line number
        "http://localhost:9000/app.js",   // url
        null, null, null,                 // url_regex, script_hash, column
        "user.isAdmin",                   // condition
    );
    defer {
        allocator.free(bp.breakpoint_id);
        for (bp.locations) |*loc| loc.deinit(allocator);
        allocator.free(bp.locations);
    }
    
    std.debug.print("Breakpoint set: {s}\n", .{bp.breakpoint_id});
    
    // Skip vendor scripts
    try dbg.setBlackboxPatterns(&.{".*vendor.*", ".*jquery.*"});
    
    // When paused, step through code
    // (In practice, you'd wait for paused event)
    try dbg.stepOver();
    try dbg.stepOver();
    try dbg.@"resume"();
    
    // Clean up
    try dbg.removeBreakpoint(bp.breakpoint_id);
    try dbg.disable();
}
```
