# Session

The `Session` struct represents an active connection to a specific browser target (tab, worker, etc.).

## Import

```zig
const cdp = @import("cdp");
const Session = cdp.Session;
```

## Overview

Sessions are created automatically when you call `browser.newPage()`. Each session is bound to a single target and identified by a unique session ID.

```zig
var session = try browser.newPage();
defer session.detach() catch {};
```

## Methods

### sendCommand

Send a CDP command to this session's target.

```zig
pub fn sendCommand(
    self: *Session,
    method: []const u8,
    params: anytype,
) !std.json.Value
```

**Parameters:**
- `method` - CDP method name (e.g., `"Page.navigate"`)
- `params` - Struct with method parameters

**Returns:** JSON response result

**Example:**

```zig
const result = try session.sendCommand("Page.navigate", .{
    .url = "https://example.com",
});
```

### detach

Detach from the target. The target (tab) remains open.

```zig
pub fn detach(self: *Session) !void
```

**Example:**

```zig
var session = try browser.newPage();
defer session.detach() catch {};

// Use session...
// On defer, session detaches but tab stays open
```

## Using Domain Clients

Domain clients are the recommended way to interact with sessions:

```zig
var session = try browser.newPage();
defer session.detach() catch {};

// Create domain clients
var page = cdp.Page.init(session);
var dom = cdp.DOM.init(session);
var runtime = cdp.Runtime.init(session);

// Enable domains
try page.enable();
try dom.enable();
try runtime.enable();

// Use typed methods
_ = try page.navigate(allocator, "https://example.com");
const doc = try dom.getDocument(allocator, 1);
const title = try runtime.evaluateAs([]const u8, "document.title");
```

## Session vs Connection

| Aspect | Connection | Session |
|--------|------------|---------|
| Scope | Browser-wide | Single target |
| Commands | Browser-level | Target-level |
| Multiple | One per browser | Multiple per browser |
| Session ID | N/A | Auto-managed |

## Example: Multiple Sessions

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

    // Create multiple sessions (tabs)
    var sessions: [3]*cdp.Session = undefined;
    for (&sessions) |*s| {
        s.* = try browser.newPage();
    }
    defer for (sessions) |s| {
        s.detach() catch {};
    };

    // Use each session independently
    for (sessions, 0..) |session, i| {
        var page = cdp.Page.init(session);
        try page.enable();
        
        const url = switch (i) {
            0 => "https://example.com",
            1 => "https://google.com",
            else => "https://github.com",
        };
        
        _ = try page.navigate(allocator, url);
    }
}
```

## Direct Command Access

For CDP methods not wrapped by domain clients:

```zig
// Use sendCommand directly
const result = try session.sendCommand("Animation.enable", .{});

// Parse response manually
const animations = try session.sendCommand("Animation.getPlaybackRate", .{});
const rate = cdp.json.getFloat(animations, "playbackRate") catch 1.0;
```

## Error Handling

```zig
const result = session.sendCommand("Page.navigate", .{
    .url = "invalid-url",
}) catch |err| switch (err) {
    error.TargetCrashed => {
        // Handle crashed target
    },
    error.SessionNotFound => {
        // Session was detached
    },
    else => return err,
};
```
