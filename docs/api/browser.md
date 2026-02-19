# Browser

The `Browser` struct manages Chrome instances and provides methods for page creation and browser-level operations.

## Import

```zig
const cdp = @import("cdp");
const Browser = cdp.Browser;
```

## Constructor

### launch

Launch a new Chrome instance.

```zig
pub fn launch(opts: LaunchOptions) !*Browser
```

**Parameters:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `allocator` | `std.mem.Allocator` | required | Memory allocator |
| `io` | `std.Io` | required | I/O context |
| `headless` | `Headless` | `.new` | Headless mode |
| `executable_path` | `?[]const u8` | `null` | Chrome binary path |
| `port` | `u16` | `0` | Debug port (0 = auto) |
| `user_data_dir` | `?[]const u8` | `null` | User data directory |
| `window_size` | `?{width, height}` | `null` | Window dimensions |
| `disable_gpu` | `bool` | `true` | Disable GPU |
| `no_sandbox` | `bool` | `false` | Disable sandbox |
| `ignore_certificate_errors` | `bool` | `false` | Skip HTTPS errors |
| `extra_args` | `?[]const []const u8` | `null` | Additional Chrome flags |
| `timeout_ms` | `u32` | `30000` | Connection timeout |

**Returns:** `*Browser` or error

**Errors:**
- `error.ChromeNotFound` - Chrome executable not found
- `error.LaunchFailed` - Failed to start Chrome
- `error.StartupTimeout` - Chrome didn't respond in time

**Example:**

```zig
var browser = try Browser.launch(.{
    .headless = .new,
    .allocator = allocator,
    .io = init.io,
    .timeout_ms = 60_000,
});
defer browser.close();
```

### connect

Connect to an existing Chrome instance.

```zig
pub fn connect(ws_url: []const u8, allocator: Allocator, io: std.Io) !*Browser
```

**Parameters:**
- `ws_url` - WebSocket URL (e.g., `ws://127.0.0.1:9222/devtools/browser/...`)
- `allocator` - Memory allocator
- `io` - I/O context

**Example:**

```zig
var browser = try Browser.connect(
    "ws://127.0.0.1:9222/devtools/browser/abc123",
    allocator,
    init.io,
);
defer browser.close();
```

## Methods

### newPage

Create a new browser tab and attach a session.

```zig
pub fn newPage(self: *Browser) !*Session
```

**Returns:** `*Session` for the new page

**Example:**

```zig
var session = try browser.newPage();
defer session.detach() catch {};
```

### pages

Get all open page targets.

```zig
pub fn pages(self: *Browser) ![]TargetInfo
```

**Returns:** Slice of `TargetInfo` (caller must free)

**Example:**

```zig
const pages = try browser.pages();
defer {
    for (pages) |*p| p.deinit(allocator);
    allocator.free(pages);
}
```

### closePage

Close a page by target ID.

```zig
pub fn closePage(self: *Browser, target_id: []const u8) !void
```

### version

Get browser version information.

```zig
pub fn version(self: *Browser) !BrowserVersion
```

**Returns:** `BrowserVersion` (caller must deinit)

**Example:**

```zig
var ver = try browser.version();
defer ver.deinit(allocator);

std.debug.print("Product: {s}\n", .{ver.product});
```

### getWsUrl

Get the WebSocket URL for this browser.

```zig
pub fn getWsUrl(self: *const Browser) []const u8
```

### close

Close the browser and clean up resources.

```zig
pub fn close(self: *Browser) void
```

Performs:
1. Sends `Browser.close` CDP command
2. Closes WebSocket connection
3. Terminates Chrome process (if launched)
4. Frees memory

## Types

### LaunchOptions

```zig
pub const LaunchOptions = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    executable_path: ?[]const u8 = null,
    headless: Headless = .new,
    port: u16 = 0,
    user_data_dir: ?[]const u8 = null,
    window_size: ?struct { width: u32, height: u32 } = null,
    ignore_certificate_errors: bool = false,
    disable_gpu: bool = true,
    no_sandbox: bool = false,
    extra_args: ?[]const []const u8 = null,
    timeout_ms: u32 = 30_000,
};
```

### Headless

```zig
pub const Headless = enum {
    off,  // GUI mode
    new,  // Chrome 112+ headless
    old,  // Legacy headless
};
```

### BrowserVersion

```zig
pub const BrowserVersion = struct {
    protocol_version: []const u8,
    product: []const u8,
    revision: []const u8,
    user_agent: []const u8,
    js_version: []const u8,

    pub fn deinit(self: *BrowserVersion, allocator: Allocator) void;
};
```

### TargetInfo

```zig
pub const TargetInfo = struct {
    target_id: []const u8,
    type: []const u8,
    title: []const u8,
    url: []const u8,
    attached: bool,
    opener_id: ?[]const u8 = null,
    browser_context_id: ?[]const u8 = null,

    pub fn deinit(self: *TargetInfo, allocator: Allocator) void;
};
```

## Complete Example

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Launch browser
    var browser = try cdp.Browser.launch(.{
        .headless = .new,
        .window_size = .{ .width = 1920, .height = 1080 },
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    // Print version
    var ver = try browser.version();
    defer ver.deinit(allocator);
    std.debug.print("Chrome: {s}\n", .{ver.product});

    // Create pages
    var session1 = try browser.newPage();
    var session2 = try browser.newPage();
    defer {
        session1.detach() catch {};
        session2.detach() catch {};
    }

    // List pages
    const pages = try browser.pages();
    defer {
        for (pages) |*p| p.deinit(allocator);
        allocator.free(pages);
    }

    std.debug.print("Open pages: {}\n", .{pages.len});
}
```
