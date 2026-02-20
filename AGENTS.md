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
.\zig-out\bin\zchrome.exe --url $url version
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
| `cli/main.zig` | CLI entry point, arg parsing, browser lifecycle |
| `cli/command_impl.zig` | Shared command implementations (session-level) |
| `cli/interactive/mod.zig` | REPL loop, tokenizer, command dispatch |
| `cli/interactive/commands.zig` | REPL command wrappers (delegate to command_impl) |
| `cli/actions/*.zig` | Low-level element/keyboard/getter actions |

## CLI Architecture

### Modular Command System

Commands are structured in three layers to avoid code duplication:

```
cli/main.zig              CLI entry point, arg parsing, browser lifecycle
cli/command_impl.zig      Shared command implementations (session + CommandCtx → action)
cli/interactive/           REPL mode
  mod.zig                 REPL loop, tokenizer, command dispatch
  commands.zig            Thin wrappers: requireSession → impl.xxx()
cli/actions/               Low-level element/keyboard actions
  mod.zig                 Re-exports from submodules
  element.zig             Click, focus, fill, scroll, drag, keyboard
  getters.zig             getText, getHtml, getValue, etc.
  selector.zig            CSS/@ref selector resolution
  upload.zig              File upload via CDP
  helpers.zig             JS string escaping, JS snippets
  types.zig               ResolvedElement, ElementPosition
```

**`cli/command_impl.zig`** is the single source of truth for all session-level
command logic. Every function has the signature:

```zig
pub fn click(session: *cdp.Session, ctx: CommandCtx) !void { ... }
```

`CommandCtx` is a lightweight struct containing `allocator`, `io`,
`positional` args, and optional flags (`output`, `full_page`, `snap_*`).

A `dispatchSessionCommand(session, command_enum, ctx)` function switches on the
command enum and calls the right implementation. It returns `false` for
commands it doesn't handle (e.g. `version`, `pages`).

**`cli/main.zig`** handles two categories of commands:
- **Browser-level** commands that manage their own session/page lifecycle
  (e.g. `navigate` creates or reuses a page and saves target to config).
  These have explicit `cmdXxx()` functions in `main.zig`.
- **Session-level** commands that just need a page session. These fall
  through to `withFirstPage()`, which finds the first real page, attaches a
  session, and calls `dispatchSessionCommand()`.

**`cli/interactive/commands.zig`** wraps each command as a 3-line function:
```zig
pub fn cmdClick(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.click(session, buildCtx(state, args));
}
```

### Session Routing

```
CLI dispatch (main.zig)
  ├─ page-level URL?      → executeDirectly()   → executeWithSession("", ...)
  ├─ --use <target-id>?   → executeOnTarget()    → executeWithSession(sid, ...)
  └─ else                 → switch on command:
       ├─ browser-level   → cmdNavigate / cmdScreenshot / cmdVersion / ...
       └─ session-level   → withFirstPage()      → dispatchSessionCommand()
```

## Common Tasks

### Adding a New CDP Domain

1. Create `src/domains/<domain>.zig`
2. Define command structs
3. Add wrapper functions to Session or Browser
4. Export from `src/root.zig`

### Adding a CLI Command

Session-level commands (that operate on an existing page) require 4 steps:

1. **Add to enum** — `Args.Command` in `cli/main.zig`
2. **Implement** — Add a `pub fn myCommand(session, ctx)` in `cli/command_impl.zig`
3. **Register dispatch** — Add a `.mycommand => try myCommand(session, ctx)` arm
   to `dispatchSessionCommand()` in `cli/command_impl.zig`
4. **Wire up REPL** — Add a `cmdMyCommand()` wrapper in
   `cli/interactive/commands.zig` and its dispatch entry in
   `cli/interactive/mod.zig`'s `executeCommand()`

That's it — `main.zig`'s `else => try withFirstPage(...)` automatically
handles CLI invocation, `--use`, and page-level URL routing.

**If the command needs custom browser-level setup** (e.g. `navigate` creates
a page and saves config, `screenshot` accepts an optional URL to navigate to
first), add an explicit `cmdXxx()` in `main.zig` and list it in the
`switch (args.command)` block. These are the minority of commands.

### Example: Adding a "highlight" Command

```zig
// 1. cli/main.zig — add to Args.Command enum
const Command = enum {
    // ... existing commands ...
    highlight,
    // ...
};

// 2. cli/command_impl.zig — implement
pub fn highlight(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: highlight <selector>\n", .{});
        return;
    }
    // ... implementation using actions_mod or cdp directly ...
    std.debug.print("Highlighted: {s}\n", .{ctx.positional[0]});
}

// 3. cli/command_impl.zig — add to dispatchSessionCommand switch
.highlight => try highlight(session, ctx),

// 4. cli/interactive/commands.zig — add REPL wrapper
pub fn cmdHighlight(state: *InteractiveState, args: []const []const u8) !void {
    const session = try requireSession(state);
    try impl.highlight(session, buildCtx(state, args));
}

// 5. cli/interactive/mod.zig — add to executeCommand()
} else if (eql(cmd, "highlight")) {
    try commands.cmdHighlight(state, args);
}
```

### Using --use Flag

The `--use <target-id>` flag allows commands to run on existing pages:
```bash
zchrome --url $url pages  # Get target IDs
zchrome --url $url --use <target-id> evaluate "document.title"
```

Implementation:
- Parsed in `parseArgs()`, stored in `Args.use_target`
- `main()` calls `executeOnTarget()` → attaches to target → `executeWithSession()`
- `executeWithSession()` calls `dispatchSessionCommand()` for session-level
  commands, falls back to browser-level commands (`version`, `pages`, etc.)

### Fixing Memory Leaks

1. Ensure all `dupe()` calls have corresponding `free()`
2. Use `defer` for cleanup
3. Check JSON Value objects are freed via their arena or manually

## Debugging Tips

### Enable Verbose Output
```powershell
.\zchrome.exe --url $url --verbose version
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
