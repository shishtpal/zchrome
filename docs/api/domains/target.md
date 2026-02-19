# Target Domain

The `Target` domain provides methods for managing browser targets (tabs, workers, etc.).

## Import

```zig
const cdp = @import("cdp");
const Target = cdp.Target;
```

## Initialization

```zig
var target = Target.init(browser.connection);
```

::: tip
Target domain operates on the connection level, not session level, as it manages targets across the browser.
:::

## Methods

### getTargets

Get all available targets.

```zig
pub fn getTargets(self: *Target, allocator: Allocator) ![]TargetInfo
```

**Returns:** Slice of `TargetInfo` (caller must deinit each and free slice)

**Example:**

```zig
const targets = try target.getTargets(allocator);
defer {
    for (targets) |*t| t.deinit(allocator);
    allocator.free(targets);
}

for (targets) |t| {
    std.debug.print("{s}: {s}\n", .{t.type, t.title});
}
```

### createTarget

Create a new target.

```zig
pub fn createTarget(
    self: *Target,
    allocator: Allocator,
    url: []const u8,
) ![]const u8
```

**Returns:** Target ID

**Example:**

```zig
const target_id = try target.createTarget(allocator, "https://example.com");
defer allocator.free(target_id);
```

### closeTarget

Close a target.

```zig
pub fn closeTarget(self: *Target, target_id: []const u8) !void
```

### activateTarget

Bring a target to foreground.

```zig
pub fn activateTarget(self: *Target, target_id: []const u8) !void
```

### attachToTarget

Attach to a target and create a session.

```zig
pub fn attachToTarget(
    self: *Target,
    allocator: Allocator,
    target_id: []const u8,
    flatten: bool,
) ![]const u8
```

**Returns:** Session ID

### detachFromTarget

Detach from a target.

```zig
pub fn detachFromTarget(self: *Target, session_id: []const u8) !void
```

### setDiscoverTargets

Enable/disable target discovery events.

```zig
pub fn setDiscoverTargets(self: *Target, discover: bool) !void
```

## Types

### TargetInfo

```zig
pub const TargetInfo = struct {
    target_id: []const u8,
    type: []const u8,          // "page", "background_page", "service_worker", etc.
    title: []const u8,
    url: []const u8,
    attached: bool,
    opener_id: ?[]const u8 = null,
    browser_context_id: ?[]const u8 = null,

    pub fn deinit(self: *TargetInfo, allocator: Allocator) void;
};
```

### Target Types

| Type | Description |
|------|-------------|
| `"page"` | Browser tab |
| `"background_page"` | Extension background |
| `"service_worker"` | Service worker |
| `"shared_worker"` | Shared worker |
| `"browser"` | Browser process |
| `"webview"` | WebView |
| `"iframe"` | Out-of-process iframe |

## Events

| Event | Description |
|-------|-------------|
| `targetCreated` | New target created |
| `targetDestroyed` | Target closed |
| `targetInfoChanged` | Target info updated |
| `attachedToTarget` | Attached to target |
| `detachedFromTarget` | Detached from target |

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

    var target = cdp.Target.init(browser.connection);

    // List all targets
    const targets = try target.getTargets(allocator);
    defer {
        for (targets) |*t| t.deinit(allocator);
        allocator.free(targets);
    }

    std.debug.print("Targets ({}):\n", .{targets.len});
    for (targets) |t| {
        std.debug.print("  [{s}] {s}: {s}\n", .{t.type, t.target_id[0..8], t.title});
    }

    // Create new targets
    const target1 = try target.createTarget(allocator, "https://example.com");
    defer allocator.free(target1);

    const target2 = try target.createTarget(allocator, "https://google.com");
    defer allocator.free(target2);

    std.debug.print("Created: {s}, {s}\n", .{target1[0..8], target2[0..8]});

    // List again
    const new_targets = try target.getTargets(allocator);
    defer {
        for (new_targets) |*t| t.deinit(allocator);
        allocator.free(new_targets);
    }

    std.debug.print("Now {} targets\n", .{new_targets.len});

    // Close one
    try target.closeTarget(target2);
}
```
