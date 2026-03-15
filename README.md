# zchrome

A Chrome DevTools Protocol (CDP) client library for Zig.

## Overview

`zchrome` provides a pure Zig implementation of the Chrome DevTools Protocol client, enabling programmatic control of Chrome/Chromium browsers. Use it for browser automation, web scraping, testing, and more.


## Project Goals
- A pure Zig implementation of the Chrome DevTools Protocol client
- A [CLI tool](#cli-commands)/[Zig library](#library-usage) for quick browser automation
- Fully portable without any daemon or service
- Ability to record and replay browser actions
- Inspired by [agent-browser](https://github.com/vercel-labs/agent-browser)
    - I have learned many things from it, although
    - I was working upon such kind of project (using rust lang), that also works, but it's not public.

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

### 1. Build

```bash
zig build -Doptimize=ReleaseFast
```

### 2. Launch Chrome

```bash
# Let zchrome launch Chrome automatically
zchrome open

# Or specify Chrome path via environment variable
export ZCHROME_BROWSER="/usr/bin/google-chrome"  # Linux/macOS
$env:ZCHROME_BROWSER = "C:\Program Files\Google\Chrome\Application\chrome.exe"  # Windows
zchrome open
zchrome connect
```

### 3. Use the CLI

```bash
# Navigate to a page
zchrome navigate https://example.com

# Take a screenshot
zchrome screenshot output.png

# Evaluate JavaScript
zchrome evaluate "document.title"

# Get browser version
zchrome version
```

> CLI state is saved per-session in `sessions/<name>/zchrome.json`

## CLI Commands

| Command | Description |
|---------|-------------|
| `open` | Launch Chrome with remote debugging |
| `connect` | Connect to running Chrome |
| `navigate <url>` | Navigate to URL |
| `screenshot <file>` | Take screenshot |
| `pdf <file>` | Save page as PDF |
| `evaluate <expr>` | Run JavaScript |
| `snapshot` | Capture accessibility tree (for AI agents) |
| `click <selector>` | Click an element |
| `fill <selector> <text>` | Fill input field |
| `version` | Display browser version info |
| `network` | Monitor network requests |
| `media list\|get` | Inspect audio/video elements |
| `cookies` | Manage cookies |
| `storage local\|session` | Get/set/clear web storage |
| `tab` | List, open, switch, close tabs |
| `session` | Manage named sessions |
| `provider` | Manage cloud browser providers |
| `cursor record\|replay` | Record/replay macros |
| `interactive` | Interactive REPL mode |

### Working with Existing Pages

> Use the `--url <ws-url>` flag to connect to an existing browser window
> Use the `--use <target-id>` flag to run commands on existing page


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

## Cloud Browser Providers

zchrome supports cloud browser providers for running automation without a local Chrome installation:

| Provider | Environment Variable |
|----------|---------------------|
| [Kernel.sh](https://kernel.sh) | `ZCHROME_KERNEL_API_KEY` |
| [Notte.cc](https://notte.cc) | `ZCHROME_NOTTE_API_KEY` |
| [Browserbase](https://browserbase.com) | `ZCHROME_BROWSERBASE_API_KEY` |
| [Browserless.io](https://browserless.io) | `ZCHROME_BROWSERLESS_API_KEY` |

```bash
# Set API key and provider
$env:ZCHROME_BROWSERLESS_API_KEY = "your-api-key"
zchrome provider set browserless

# Create cloud browser session
zchrome open

# Use like local Chrome
zchrome navigate https://example.com
zchrome screenshot output.png

# Close when done
zchrome provider close
```

See [Cloud Providers Guide](docs/cli/providers.md) for details.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ZCHROME_SESSION` | Default session name (default: "default") |
| `ZCHROME_BROWSER` | Chrome/Chromium executable path |
| `ZCHROME_PORT` | Debug port (default: 9222) |
| `ZCHROME_DATA_DIR` | Chrome user data directory |
| `ZCHROME_HEADLESS` | Headless mode: "new", "old", or "off" |
| `ZCHROME_VERBOSE` | Enable verbose output ("1" or "true") |
| `ZCHROME_PROVIDER` | Cloud provider: "local", "kernel", "notte", "browserbase", "browserless" |

See [Environment Variables Guide](docs/guide/environment.md) for details.

## Sessions

zchrome supports named sessions for isolated Chrome configurations:

```bash
# Use different sessions for different projects
zchrome --session work open --port 9222
zchrome --session personal open --port 9223

# Or use environment variable
export ZCHROME_SESSION=work
zchrome navigate https://example.com
```

Each session maintains its own config, Chrome profile, and cookies. See [CLI Sessions Guide](docs/guide/cli-sessions.md).

## Macro Recording & Testing

Record and replay browser interactions with built-in assertions:

```bash
# Record interactions to a file
zchrome cursor record login-flow.json
# (interact with the browser, press Enter to stop)

# Replay the recording
zchrome cursor replay login-flow.json --interval=200-500

# Replay with assertions and retry logic
zchrome cursor replay form.json --retries 5 --retry-delay 2000

# With fallback on failure
zchrome cursor replay form.json --fallback error-handler.json
```

Macros use semantic commands (click, fill, press, **assert**) with CSS selectors, making them human-readable and editable. The `assert` action tests application state during replay with automatic retry on failure. See [Macro Guide](docs/examples/macros.md).

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
- [Agent Browser](https://github.com/vercel-labs/agent-browser)
- [Zig Documentation](https://ziglang.org/documentation/)
