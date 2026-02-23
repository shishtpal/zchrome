# Architecture

This page describes the internal architecture of zchrome and how its components interact.

## Layer Overview

```
┌─────────────────────────────────────────────────┐
│ CLI (cli/main.zig)                              │  User interface
├─────────────────────────────────────────────────┤
│ Browser Launcher (browser/)                      │  Process management
├─────────────────────────────────────────────────┤
│ Domain Clients (domains/*)                       │  11 CDP domains
├─────────────────────────────────────────────────┤
│ Core Protocol (core/)                            │  JSON-RPC, sessions
├─────────────────────────────────────────────────┤
│ Transport (transport/)                           │  WebSocket + Pipe
├─────────────────────────────────────────────────┤
│ Utilities (util/)                                │  JSON, base64, URL
└─────────────────────────────────────────────────┘
```

## Directory Structure

```
zchrome/
├── src/
│   ├── root.zig            # Public API exports
│   ├── browser/
│   │   ├── launcher.zig    # Chrome discovery and launch
│   │   ├── options.zig     # Launch configuration
│   │   └── process.zig     # Child process lifecycle
│   ├── core/
│   │   ├── connection.zig  # Top-level connection orchestrator
│   │   ├── session.zig     # Per-target session multiplexing
│   │   ├── protocol.zig    # JSON-RPC message parsing
│   │   └── types.zig       # Type aliases (SessionId, TargetId, etc.)
│   ├── transport/
│   │   ├── websocket.zig   # RFC 6455 WebSocket client
│   │   ├── ws_server.zig   # WebSocket server for event streaming
│   │   └── pipe.zig        # Stdio pipe transport
│   ├── domains/
│   │   ├── page.zig        # Navigation, screenshots, PDF
│   │   ├── dom.zig         # DOM querying and manipulation
│   │   ├── runtime.zig     # JavaScript evaluation
│   │   ├── network.zig     # Network request tracking
│   │   ├── input.zig       # Mouse/keyboard events
│   │   ├── target.zig      # Tab/target management
│   │   ├── emulation.zig   # Device emulation
│   │   ├── fetch.zig       # Network interception
│   │   ├── performance.zig # Metrics collection
│   │   ├── browser.zig     # Version info, window management
│   │   └── storage.zig     # Cookies, local storage
│   └── util/
│       ├── json.zig        # JSON decode/encode helpers
│       ├── base64.zig      # Base64 encoding/decoding
│       ├── url.zig         # URL parsing
│       └── retry.zig       # Exponential backoff
├── cli/
│   └── main.zig            # CLI application
├── tests/                  # Test suite
└── protocol/               # Upstream CDP JSON schemas
```

## Component Details

### Browser Launcher

The `Browser` struct manages the Chrome lifecycle:

1. **Discovery** - Finds Chrome executable on the system
2. **Launch** - Spawns Chrome with appropriate flags
3. **Connection** - Establishes WebSocket connection
4. **Cleanup** - Terminates process on close

```zig
pub const Browser = struct {
    connection: *Connection,
    process: ?*ChromeProcess,
    allocator: std.mem.Allocator,
    ws_url: []const u8,
};
```

### Connection & Sessions

- **Connection** manages the WebSocket transport and command routing
- **Session** provides per-tab isolation with session IDs

```zig
// One connection to browser
var browser = try Browser.launch(...);

// Multiple sessions (tabs)
var session1 = try browser.newPage();
var session2 = try browser.newPage();
```

### Domain Clients

Domain clients are thin wrappers that:
1. Take a `Session` reference
2. Provide typed methods for CDP commands
3. Parse responses into Zig structs

```zig
pub const Page = struct {
    session: *Session,

    pub fn navigate(self: *Self, allocator: Allocator, url: []const u8) !NavigateResult {
        const result = try self.session.sendCommand("Page.navigate", .{ .url = url });
        // Parse and return typed result
    }
};
```

### Transport Layer

Two transport options:

| Transport | Use Case | Protocol |
|-----------|----------|----------|
| **WebSocket** | Default, network-based | RFC 6455 |
| **Pipe** | Same-machine, stdin/stdout | `--remote-debugging-pipe` |

### JSON-RPC Protocol

CDP uses JSON-RPC 2.0 messages:

```json
// Request
{ "id": 1, "method": "Page.navigate", "params": { "url": "..." } }

// Response
{ "id": 1, "result": { "frameId": "..." } }

// Event
{ "method": "Page.loadEventFired", "params": { "timestamp": 123.45 } }
```

## Threading Model

- **Main thread**: Sends commands, processes results
- **Read thread**: Receives messages from WebSocket
- **Mutex protection**: Thread-safe command sending

## Memory Management

zchrome uses explicit allocator passing:

```zig
// Caller provides allocator
const result = try page.navigate(allocator, url);

// Caller owns result, must deinit
defer result.deinit(allocator);
```

No hidden allocations - every allocation goes through the provided allocator.

## Error Handling

Four error categories:

| Error Set | Cause |
|-----------|-------|
| `TransportError` | WebSocket/network issues |
| `ProtocolError` | Invalid CDP messages |
| `CdpError` | Chrome-reported errors |
| `LaunchError` | Browser startup failures |

```zig
pub const TransportError = error{
    ConnectionRefused,
    ConnectionClosed,
    HandshakeFailed,
    TlsError,
    Timeout,
};
```
