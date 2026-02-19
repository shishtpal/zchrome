# AGENTS.md

This document provides context for AI agents working on the zchrome codebase.

## Project Overview

`zchrome` is a Chrome DevTools Protocol (CDP) client library for Zig. It enables programmatic control of Chrome/Chromium browsers via the DevTools Protocol.

## Target Zig Version

**Zig 0.16.0-dev.2535+b5bd49460**

This is a development version with significant API changes from Zig 0.11/0.12. Key breaking changes:

### ArrayList API
```zig
// Old (Zig 0.11)
var list = std.ArrayList(T).init(allocator);

// New (Zig 0.16)
var list: std.ArrayList(T) = .empty;
try list.append(allocator, item);
```

### Io Context
Most I/O operations now require an `std.Io` context:
- File operations: `std.fs.cwd()` → requires `Io` context
- Networking: `std.Io.net.IpAddress.connect()`
- Process spawning: `std.process.spawn(io, options)`

### Time Functions Removed
```zig
// Old
std.time.sleep(ms * std.time.ns_per_ms);

// New (spin loop)
var i: u32 = 0;
while (i < iterations) : (i += 1) {
    std.atomic.spinLoopHint();
}
```

### JSON Value Types
```zig
// std.json.Value is a union
std.json.Value{ .string = "value" }
std.json.Value{ .integer = 42 }
std.json.Value{ .object = std.json.ObjectMap.init(allocator) }
std.json.Value{ .array = std.json.Array.init(allocator) }
```

## Architecture

### Core Components

1. **Connection** (`src/core/connection.zig`)
   - Manages WebSocket connection to Chrome
   - Sends commands and receives responses
   - Synchronous request/response model (no threading in Zig 0.16)

2. **WebSocket** (`src/transport/websocket.zig`)
   - RFC 6455 WebSocket client
   - Uses `std.Io.net.Stream` for TCP connections
   - Handles framing, masking, and protocol handshake

3. **Browser** (`src/browser/launcher.zig`)
   - Browser lifecycle management
   - `connect()` - Connect to existing Chrome instance
   - `launch()` - Spawn new Chrome process (stubbed)
   - `disconnect()` - Close connection without terminating Chrome
   - `close()` - Terminate Chrome

4. **Session** (`src/core/session.zig`)
   - Represents a target (page, worker, etc.)
   - Commands are scoped to a session via `sessionId`

5. **Domains** (`src/domains/`)
   - Type-safe wrappers for CDP domains
   - Page, Runtime, DOM, Network, Storage, Target, etc.

### Data Flow

```
CLI/User Code
    ↓
Browser.connect(url) → Connection.open(url) → WebSocket.connect()
    ↓
Session.sendCommand(method, params) → Connection.sendCommand()
    ↓
WebSocket.sendText(json) → TCP Stream
    ↓
WebSocket.receiveMessage() → JSON Response
    ↓
Parsed result returned to caller
```

## Key Implementation Details

### WebSocket Handshake

```zig
// Parse ws:// URL
const host = "127.0.0.1";
const port = 9222;
const path = "/devtools/browser/<guid>";

// Connect
const stream = std.Io.net.IpAddress.connect(address, io, .{
    .mode = .stream,
    .protocol = .tcp,
});

// Send HTTP upgrade
const request = "GET /devtools/browser/... HTTP/1.1\r\n" ++
    "Host: 127.0.0.1:9222\r\n" ++
    "Upgrade: websocket\r\n" ++
    "Connection: Upgrade\r\n" ++
    "Sec-WebSocket-Key: <base64>\r\n" ++
    "Sec-WebSocket-Version: 13\r\n" ++
    "\r\n";

// Verify 101 Switching Protocols
```

### CDP Command Format

```json
{
  "id": 1,
  "method": "Page.navigate",
  "params": { "url": "https://example.com" },
  "sessionId": "optional-session-id"
}
```

### CDP Response Format

```json
{
  "id": 1,
  "result": { ... },
  "sessionId": "optional-session-id"
}
```

Or error:
```json
{
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Invalid params"
  }
}
```

## Known Issues & Workarounds

### Memory Leaks in Debug Mode
Debug builds with the General Purpose Allocator (GPA) detect memory leaks from JSON cloning. Use `ReleaseFast` for production:
```bash
zig build -Doptimize=ReleaseFast
```

### Chrome Termination on Exit
When connecting via `--url`, use `disconnect()` not `close()`:
- `disconnect()` - Closes WebSocket, Chrome keeps running
- `close()` - Sends `Browser.close` command, terminates Chrome

### Empty Slice Bug
The Zig 0.16 `netWrite` function crashes with empty slices:
```zig
// WRONG - crashes
io.vtable.netWrite(..., data, &.{}, 0);

// CORRECT - use Stream.writer() instead
var writer = stream.writer(io, buffer);
writer.interface.writeAll(data);
```

### IP Address Only
`std.Io.net.IpAddress.parse()` only accepts numeric IPs, not hostnames:
```zig
// Works
const addr = std.Io.net.IpAddress.parse("127.0.0.1", 9222);

// Does NOT work (no DNS resolution)
const addr = std.Io.net.IpAddress.parse("example.com", 80);
```

## Testing

### Manual Testing with Chrome

1. Start Chrome:
```powershell
& $env:CHROME_EXECUTABLE --remote-debugging-port=9222 --user-data-dir="D:\tmp\chrome-dev-profile"
```

2. Get WebSocket URL:
```powershell
$url = (Invoke-RestMethod http://127.0.0.1:9222/json/version).webSocketDebuggerUrl
```

3. Test CLI:
```powershell
.\zig-out\bin\cdp-cli.exe --url $url version
```

### Unit Tests

```bash
zig build test
```

## File Reference

| File | Purpose |
|------|---------|
| `src/root.zig` | Library entry point, exports |
| `src/core/connection.zig` | WebSocket connection, command sending |
| `src/core/session.zig` | Target session management |
| `src/core/protocol.zig` | CDP types, serialization |
| `src/transport/websocket.zig` | WebSocket client implementation |
| `src/browser/launcher.zig` | Browser connect/launch/close |
| `src/browser/process.zig` | Process spawning (stubbed) |
| `src/domains/*.zig` | CDP domain wrappers |
| `src/util/json.zig` | JSON parsing helpers |
| `cli/main.zig` | CLI implementation |

## Common Tasks

### Adding a New CDP Domain

1. Create `src/domains/<domain>.zig`
2. Define command structs
3. Add wrapper functions to Session or Browser
4. Export from `src/root.zig`

### Adding a CLI Command

1. Add command to `Args.Command` enum in `cli/main.zig`
2. Implement `cmd<Command>` function
3. Add to switch statement in `main()`
4. If command supports `--use` flag, implement `cmd<Command>WithSession` variant

### Using --use Flag

The `--use <target-id>` flag allows commands to run on existing pages:
```bash
cdp-cli --url $url pages  # Get target IDs
cdp-cli --url $url --use <target-id> evaluate "document.title"
```

Implementation:
- Parse `--use` flag in `parseArgs()`
- Store target ID in `Args.use_target`
- Call `executeOnTarget()` instead of normal command flow
- Create session from target ID and call `cmd<Command>WithSession()`

### Fixing Memory Leaks

1. Ensure all `dupe()` calls have corresponding `free()`
2. Use `defer` for cleanup
3. Check JSON Value objects are freed via their arena or manually

## Debugging Tips

### Enable Verbose Output
```powershell
.\cdp-cli.exe --url $url --verbose version
```

### Check Chrome is Running
```powershell
Invoke-RestMethod http://127.0.0.1:9222/json/version
```

### List All Targets
```powershell
Invoke-RestMethod http://127.0.0.1:9222/json
```

## Related Documentation

- Chrome DevTools Protocol: https://chromedevtools.github.io/devtools-protocol/
