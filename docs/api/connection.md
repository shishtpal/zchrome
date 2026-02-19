# Connection

The `Connection` struct manages the WebSocket transport and CDP command routing.

::: tip
Most users interact with `Browser` rather than `Connection` directly. Use `Connection` when you need low-level protocol access.
:::

## Import

```zig
const cdp = @import("cdp");
const Connection = cdp.Connection;
```

## Constructor

### open

Open a WebSocket connection to Chrome.

```zig
pub fn open(ws_url: []const u8, opts: OpenOptions) !*Connection
```

**Parameters:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `allocator` | `std.mem.Allocator` | required | Memory allocator |
| `io` | `std.Io` | required | I/O context |
| `receive_timeout_ms` | `u32` | `30000` | Command timeout |

**Example:**

```zig
const connection = try Connection.open(
    "ws://127.0.0.1:9222/devtools/browser/...",
    .{
        .allocator = allocator,
        .io = init.io,
        .receive_timeout_ms = 60_000,
    },
);
defer connection.close();
```

## Methods

### sendCommand

Send a CDP command and wait for response.

```zig
pub fn sendCommand(
    self: *Connection,
    method: []const u8,
    params: anytype,
    session_id: ?[]const u8,
) !std.json.Value
```

**Parameters:**
- `method` - CDP method name (e.g., `"Page.navigate"`)
- `params` - Struct with method parameters
- `session_id` - Optional session ID for target-specific commands

**Returns:** JSON response result

**Example:**

```zig
const result = try connection.sendCommand("Browser.getVersion", .{}, null);
```

### createSession

Create a session for a target.

```zig
pub fn createSession(self: *Connection, target_id: []const u8) !*Session
```

**Parameters:**
- `target_id` - Target ID to attach to

**Returns:** New session handle

### close

Close the connection and clean up resources.

```zig
pub fn close(self: *Connection) void
```

## Low-Level Access

For advanced use cases, you can access the underlying transport:

```zig
// Browser provides connection access
const connection = browser.connection;

// Send raw command
const result = try connection.sendCommand(
    "Target.getTargets",
    .{},
    null,
);
```

## Error Types

```zig
pub const TransportError = error{
    ConnectionRefused,
    ConnectionClosed,
    ConnectionReset,
    HandshakeFailed,
    TlsError,
    FrameTooLarge,
    InvalidFrame,
    Timeout,
};
```

## Example: Direct Connection

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Connect directly (requires running Chrome)
    const connection = try cdp.Connection.open(
        "ws://127.0.0.1:9222/devtools/browser/abc123",
        .{
            .allocator = allocator,
            .io = init.io,
        },
    );
    defer connection.close();

    // Get version
    const version = try connection.sendCommand("Browser.getVersion", .{}, null);
    
    // Create target
    const create_result = try connection.sendCommand("Target.createTarget", .{
        .url = "about:blank",
    }, null);

    // Attach session
    const target_id = cdp.json.getString(create_result, "targetId") catch unreachable;
    var session = try connection.createSession(target_id);
    defer session.detach() catch {};

    // Use session...
    _ = try session.sendCommand("Page.navigate", .{ .url = "https://example.com" });
}
```
