# zchrome

A Chrome DevTools Protocol (CDP) client library for Zig.

## Overview

`zchrome` provides a pure Zig implementation of the Chrome DevTools Protocol client, enabling programmatic control of Chrome/Chromium browsers. Use it for browser automation, web scraping, testing, and more.

## Features

- **WebSocket Transport** - Direct WebSocket connection to Chrome's DevTools Protocol
- **CDP Domains** - Support for Page, Runtime, DOM, Network, Storage, Target, and more
- **Type-Safe API** - Leverage Zig's compile-time features for type-safe CDP commands
- **CLI Tool** - Built-in command-line interface for quick browser automation

## Requirements

- Zig 0.16.0-dev or later
- Chrome/Chromium browser

## Installation

Add to your `build.zig.zon`:

```zig
.{
    .name = "cdp",
    .version = "0.1.0",
    .dependencies = .{
        .cdp = .{
            .url = "https://github.com/shishtpal/zchrome/archive/main.tar.gz",
            .hash = "...",
        },
    },
}
```

## Quick Start

### 1. Start Chrome with Remote Debugging

```bash
# Windows
chrome.exe --remote-debugging-port=9222 --user-data-dir="C:\tmp\chrome-dev-profile"

# Linux
google-chrome --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-dev-profile

# macOS
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-dev-profile
```

### 2. Get WebSocket URL

```bash
curl http://127.0.0.1:9222/json/version
```

### 3. Use the CLI

```bash
# Build
zig build -Doptimize=ReleaseFast

# Get browser version
zchrome --url ws://127.0.0.1:9222/devtools/browser/<guid> version

# Navigate to a page
zchrome --url ws://127.0.0.1:9222/devtools/browser/<guid> navigate https://example.com

# Take a screenshot
zchrome --url ws://127.0.0.1:9222/devtools/browser/<guid> screenshot output.png

# Evaluate JavaScript
zchrome --url ws://127.0.0.1:9222/devtools/browser/<guid> evaluate "document.title"
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `version` | Display browser version info |
| `navigate <url>` | Navigate to URL |
| `screenshot <file>` | Take screenshot |
| `pdf <file>` | Save page as PDF |
| `evaluate <expr>` | Run JavaScript |
| `dom <selector>` | Print DOM structure |
| `network` | Monitor network requests |
| `cookies` | List, set, or clear cookies |
| `storage local\|session` | Get/set/clear web storage |
| `list-targets` | List all targets |
| `pages` | List all pages with target IDs |
| `interactive` | Interactive REPL mode |

### Working with Existing Pages

Use the `--use <target-id>` flag to run commands on existing pages:

```bash
# List open pages
zchrome --url $url pages

# Run commands on existing page
zchrome --url $url --use <target-id> evaluate "document.title"
zchrome --url $url --use <target-id> navigate https://example.org
zchrome --url $url --use <target-id> screenshot --output page.png
```

## Library Usage

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Connect to Chrome
    var browser = try cdp.Browser.connect(
        "ws://127.0.0.1:9222/devtools/browser/<guid>",
        allocator,
        io,
    );
    defer browser.disconnect();

    // Get browser version
    const version = try browser.version();
    defer {
        allocator.free(version.protocol_version);
        allocator.free(version.product);
        allocator.free(version.user_agent);
    }

    std.debug.print("Browser: {s}\n", .{version.product});

    // Create a new page
    var session = try browser.newPage();
    defer session.detach() catch {};

    // Navigate
    _ = try session.sendCommand("Page.navigate", .{
        .url = "https://example.com",
    }, null);

    // Evaluate JavaScript
    const result = try session.sendCommand("Runtime.evaluate", .{
        .expression = "document.title",
    }, null);

    std.debug.print("Title: {s}\n", .{result.object.get("result").?.object.get("value").?.string});
}
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `version` | Display browser version info |
| `navigate <url>` | Navigate to URL |
| `screenshot <file>` | Take screenshot |
| `pdf <file>` | Save page as PDF |
| `evaluate <expr>` | Run JavaScript |
| `dom` | Print DOM structure |
| `network` | Monitor network requests |
| `cookies` | List, set, or clear cookies |
| `storage local` | Get/set/clear localStorage |
| `storage session` | Get/set/clear sessionStorage |
| `list-targets` | List open targets |
| `interactive` | Interactive REPL mode |

## CDP Domains

The library supports the following Chrome DevTools Protocol domains:

- **Browser** - Browser information and management
- **Page** - Page navigation, screenshots, PDF generation
- **Runtime** - JavaScript execution
- **DOM** - DOM inspection and manipulation
- **Network** - Network monitoring and interception
- **Storage** - Cookies, local storage, session storage
- **Target** - Target management and session attachment
- **Emulation** - Device emulation
- **Input** - Input simulation
- **Performance** - Performance metrics

## Building

```bash
# Debug build (with leak detection)
zig build

# Release build (recommended)
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

## Project Structure

```
zchrome/
├── src/
│   ├── root.zig           # Main library entry point
│   ├── core/
│   │   ├── connection.zig # WebSocket connection handling
│   │   ├── protocol.zig   # CDP protocol types
│   │   └── session.zig    # Session management
│   ├── transport/
│   │   └── websocket.zig  # WebSocket client
│   ├── browser/
│   │   ├── launcher.zig   # Browser launch/connect
│   │   └── process.zig    # Process management
│   ├── domains/
│   │   ├── page.zig       # Page domain
│   │   ├── runtime.zig    # Runtime domain
│   │   ├── dom.zig        # DOM domain
│   │   ├── network.zig    # Network domain
│   │   └── ...
│   └── util/
│       └── json.zig       # JSON utilities
├── cli/
│   └── main.zig           # CLI implementation
├── build.zig              # Build configuration
└── build.zig.zon          # Dependencies
```

## Limitations

- **TLS/SSL** - Not yet supported (wss:// URLs)
- **DNS Resolution** - Requires numeric IP addresses (not hostnames)
- **Process Spawning** - Chrome auto-launch is stubbed; use manual launch
- **File I/O** - Screenshot/PDF saving requires manual implementation

## Compatibility

Tested with:
- Zig 0.16.0-dev.2535+b5bd49460
- Chrome 145.x

## License

MIT License

## Contributing

Contributions welcome! Please ensure all tests pass before submitting a PR.

```bash
zig build test
```

## Resources

- [Chrome DevTools Protocol Documentation](https://chromedevtools.github.io/devtools-protocol/)
- [Zig Documentation](https://ziglang.org/documentation/)
