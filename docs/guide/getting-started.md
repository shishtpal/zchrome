# Getting Started

This guide will help you install zchrome and write your first browser automation script.

## Prerequisites

- **Zig** 0.16.0-dev.2535 or later
- **Chrome** or **Chromium** browser installed

### Verify Zig Installation

```bash
zig version
# Should output: 0.16.0-dev.2535+... or later
```

### Chrome Installation

zchrome automatically discovers Chrome in standard locations:

**Windows:**
- `C:\Program Files\Google\Chrome\Application\chrome.exe`
- `C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`

**macOS:**
- `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`

**Linux:**
- `/usr/bin/google-chrome`
- `/usr/bin/chromium`
- `/snap/bin/chromium`

## Installation

Add zchrome to your `build.zig.zon`:

```zig
.dependencies = .{
    .cdp = .{
        .url = "https://github.com/shishtpal/zchrome/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const cdp = b.dependency("cdp", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("cdp", cdp.module("cdp"));
```

## Basic Usage

### Launch Browser and Navigate

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Launch Chrome in headless mode
    var browser = try cdp.Browser.launch(.{
        .headless = .new,
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    // Create a new page
    var session = try browser.newPage();
    defer session.detach() catch {};

    // Initialize Page domain
    var page = cdp.Page.init(session);
    try page.enable();

    // Navigate to URL
    var result = try page.navigate(allocator, "https://example.com");
    defer result.deinit(allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    std.debug.print("Navigated to frame: {s}\n", .{result.frame_id});
}
```

### Capture Screenshot

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

    var session = try browser.newPage();
    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, "https://example.com");

    // Capture PNG screenshot
    const screenshot_data = try page.captureScreenshot(allocator, .{
        .format = .png,
    });
    defer allocator.free(screenshot_data);

    // Decode base64
    const decoded = try cdp.base64.decodeAlloc(allocator, screenshot_data);
    defer allocator.free(decoded);

    std.debug.print("Screenshot: {} bytes\n", .{decoded.len});
}
```

### Execute JavaScript

```zig
var runtime = cdp.Runtime.init(session);
try runtime.enable();

// Get page title
const title = try runtime.evaluateAs([]const u8, "document.title");
std.debug.print("Title: {s}\n", .{title});

// Execute complex expression
var result = try runtime.evaluate(allocator, "1 + 2", .{
    .return_by_value = true,
});
defer result.deinit(allocator);
```

### Query DOM

```zig
var dom = cdp.DOM.init(session);
try dom.enable();

// Get document
const doc = try dom.getDocument(allocator, 1);
defer {
    var d = doc;
    d.deinit(allocator);
}

// Query selector
const node_id = try dom.querySelector(doc.node_id, "h1");
const html = try dom.getOuterHTML(allocator, node_id);
defer allocator.free(html);

std.debug.print("H1 content: {s}\n", .{html});
```

## Launch Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `headless` | `Headless` | `.new` | Headless mode (`.new`, `.old`, `.off`) |
| `executable_path` | `?[]const u8` | `null` | Custom Chrome path |
| `port` | `u16` | `0` | Debug port (0 = auto) |
| `user_data_dir` | `?[]const u8` | `null` | User data directory |
| `window_size` | `?{width, height}` | `null` | Browser window size |
| `disable_gpu` | `bool` | `true` | Disable GPU acceleration |
| `no_sandbox` | `bool` | `false` | Disable sandbox |
| `timeout_ms` | `u32` | `30000` | Connection timeout |

## Connect to Existing Browser

Instead of launching, connect to an already running Chrome:

```bash
# Start Chrome with debugging enabled
chrome --remote-debugging-port=9222
```

```zig
var browser = try cdp.Browser.connect(
    "ws://127.0.0.1:9222/devtools/browser/...",
    allocator,
    init.io,
);
defer browser.close();
```

## Using the CLI

zchrome includes a command-line tool for quick tasks:

```bash
# Build the CLI (use ReleaseFast to avoid debug allocator errors)
zig build -Doptimize=ReleaseFast

# Launch Chrome with remote debugging
zchrome open --chrome "/path/to/chrome" --data-dir "/tmp/chrome-profile"

# Connect and save WebSocket URL to zchrome.json
zchrome connect

# Navigate (uses existing page, saves target ID)
zchrome navigate https://example.com

# Subsequent commands use saved config automatically
zchrome evaluate "document.title"
zchrome screenshot --output page.png
zchrome screenshot --output full.png --full  # Full page screenshot
zchrome pdf --output page.pdf

# Query DOM
zchrome dom "h1"

# Get browser version
zchrome version
```

### Config File

zchrome stores session info in `zchrome.json`:

```json
{
  "chrome_path": "/path/to/chrome",
  "data_dir": "/tmp/chrome-profile",
  "port": 9222,
  "ws_url": "ws://127.0.0.1:9222/devtools/browser/...",
  "last_target": "DC6E72F7B31F6A70C4C2B7A2D5A9ED74"
}
```

### Working with Multiple Pages

```bash
# List all open pages
zchrome pages

# Output:
# TARGET ID                                 TITLE                          URL
# --------------------------------------------------------------------------------------------------------------------------
# 75E5402CE67C63D19659EEFDC1CF292D          Example Domain                 https://example.com/
# Total: 1 page(s)

# Execute on a specific page
zchrome --use 75E5402CE67C63D19659EEFDC1CF292D evaluate "document.title"

# Navigate a specific page
zchrome --use 75E5402CE67C63D19659EEFDC1CF292D navigate https://example.org

# Take full page screenshot of specific page
zchrome --use 75E5402CE67C63D19659EEFDC1CF292D screenshot --output page.png --full
```

## Next Steps

- [Browser Management](/guide/browser-management) - Advanced browser control
- [Sessions & Targets](/guide/sessions) - Multi-tab workflows
- [Error Handling](/guide/error-handling) - Handle errors gracefully
- [API Reference](/api/browser) - Full API documentation
