# Error Handling

zchrome uses Zig's error handling system with categorized error sets for different failure modes.

## Error Categories

### TransportError

Network and WebSocket errors:

```zig
pub const TransportError = error{
    ConnectionRefused,   // Chrome not reachable
    ConnectionClosed,    // Connection dropped
    ConnectionReset,     // Connection reset by peer
    HandshakeFailed,     // WebSocket handshake failed
    TlsError,           // TLS/SSL error
    FrameTooLarge,      // WebSocket frame exceeds limit
    InvalidFrame,       // Malformed WebSocket frame
    Timeout,            // Operation timed out
};
```

### ProtocolError

CDP message parsing errors:

```zig
pub const ProtocolError = error{
    InvalidMessage,      // Malformed JSON-RPC message
    UnexpectedResponse,  // Response doesn't match request
    MissingField,       // Required field not present
    TypeMismatch,       // Field has unexpected type
};
```

### CdpError

Chrome DevTools Protocol errors:

```zig
pub const CdpError = error{
    TargetCrashed,      // Target (page) crashed
    TargetClosed,       // Target was closed
    SessionNotFound,    // Session ID invalid
    MethodNotFound,     // CDP method doesn't exist
    InvalidParams,      // Invalid method parameters
    InternalError,      // Chrome internal error
    GenericCdpError,    // Other CDP error
};
```

### LaunchError

Browser startup errors:

```zig
pub const LaunchError = error{
    ChromeNotFound,     // Chrome executable not found
    LaunchFailed,       // Failed to start process
    WsUrlParseError,    // Couldn't parse WebSocket URL
    StartupTimeout,     // Chrome didn't start in time
};
```

## Error Handling Patterns

### Basic Try-Catch

```zig
const result = page.navigate(allocator, url) catch |err| {
    std.debug.print("Navigation failed: {}\n", .{err});
    return err;
};
```

### Switch on Error

```zig
var browser = cdp.Browser.launch(.{ ... }) catch |err| switch (err) {
    error.ChromeNotFound => {
        std.debug.print("Chrome not found!\n", .{});
        std.debug.print("Install Chrome or specify path with --chrome\n", .{});
        std.process.exit(1);
    },
    error.StartupTimeout => {
        std.debug.print("Chrome startup timed out. Try increasing timeout.\n", .{});
        std.process.exit(1);
    },
    error.ConnectionRefused => {
        std.debug.print("Could not connect to Chrome.\n", .{});
        std.process.exit(1);
    },
    else => {
        std.debug.print("Unexpected error: {}\n", .{err});
        return err;
    },
};
```

### Handling Navigation Errors

Navigation can fail even without throwing:

```zig
var result = try page.navigate(allocator, url);
defer result.deinit(allocator);

if (result.error_text) |err_text| {
    std.debug.print("Navigation error: {s}\n", .{err_text});
    // Handle: net::ERR_NAME_NOT_RESOLVED, net::ERR_CONNECTION_REFUSED, etc.
    return;
}

std.debug.print("Successfully navigated to frame: {s}\n", .{result.frame_id});
```

### Handling JavaScript Errors

```zig
var result = try runtime.evaluate(allocator, expression, .{
    .return_by_value = true,
});
defer result.deinit(allocator);

if (result.exception_details) |exception| {
    std.debug.print("JavaScript error: {s}\n", .{exception.text});
    return;
}
```

### Graceful Session Cleanup

```zig
var session = try browser.newPage();
defer {
    // Use catch {} to ignore errors during cleanup
    session.detach() catch {};
}
```

## Timeout Handling

### Launch Timeout

```zig
var browser = try cdp.Browser.launch(.{
    .timeout_ms = 60_000, // 60 second timeout
    .allocator = allocator,
    .io = init.io,
});
```

### Command Timeout

Commands use the connection's receive timeout:

```zig
const connection = try Connection.open(ws_url, .{
    .allocator = allocator,
    .io = init.io,
    .receive_timeout_ms = 30_000, // 30 seconds per command
});
```

## Retry Logic

zchrome includes a retry utility:

```zig
const retry = @import("cdp").retry;

// Retry with exponential backoff
const result = try retry.withBackoff(3, struct {
    fn attempt() !Response {
        return session.sendCommand("Page.navigate", .{ .url = url });
    }
}.attempt);
```

## Common Error Scenarios

### Chrome Not Found

```zig
if (cdp.Browser.launch(.{ ... })) |browser| {
    // Success
} else |err| if (err == error.ChromeNotFound) {
    // Suggest installation or manual path
}
```

### Target Crashed

```zig
const result = page.captureScreenshot(allocator, .{}) catch |err| {
    if (err == error.TargetCrashed) {
        // Page crashed, create new page
        session.detach() catch {};
        var new_session = try browser.newPage();
        // Retry operation
    }
    return err;
};
```

### Connection Lost

```zig
while (true) {
    const cmd_result = session.sendCommand("Page.navigate", .{ .url = url }) catch |err| {
        if (err == error.ConnectionClosed or err == error.ConnectionReset) {
            // Reconnect
            browser.close();
            browser = try cdp.Browser.launch(.{ ... });
            session = try browser.newPage();
            continue;
        }
        return err;
    };
    break;
}
```

## Best Practices

1. **Always use defer for cleanup**
   ```zig
   var browser = try cdp.Browser.launch(.{ ... });
   defer browser.close();
   ```

2. **Check NavigateResult.error_text**
   ```zig
   if (result.error_text) |err| {
       // Handle navigation failure
   }
   ```

3. **Handle session detach errors gracefully**
   ```zig
   defer session.detach() catch {};
   ```

4. **Set appropriate timeouts**
   ```zig
   .timeout_ms = 60_000, // For slow pages
   ```

5. **Log errors with context**
   ```zig
   std.debug.print("Failed to navigate to {s}: {}\n", .{url, err});
   ```
