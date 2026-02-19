# Browser Management

This guide covers launching, configuring, and managing Chrome instances.

## Launching Chrome

### Basic Launch

```zig
var browser = try cdp.Browser.launch(.{
    .allocator = allocator,
    .io = init.io,
});
defer browser.close();
```

### Headless Modes

Chrome offers multiple headless modes:

```zig
// New headless (Chrome 112+) - recommended
var browser = try cdp.Browser.launch(.{
    .headless = .new,
    .allocator = allocator,
    .io = init.io,
});

// Old headless mode
var browser = try cdp.Browser.launch(.{
    .headless = .old,
    // ...
});

// GUI mode (visible browser)
var browser = try cdp.Browser.launch(.{
    .headless = .off,
    // ...
});
```

| Mode | Description |
|------|-------------|
| `.new` | Chrome 112+ headless, better compatibility |
| `.old` | Legacy headless, faster but less accurate |
| `.off` | Visible browser window |

### Custom Chrome Path

```zig
var browser = try cdp.Browser.launch(.{
    .executable_path = "/path/to/chrome",
    .allocator = allocator,
    .io = init.io,
});
```

### Window Size

```zig
var browser = try cdp.Browser.launch(.{
    .window_size = .{
        .width = 1920,
        .height = 1080,
    },
    .allocator = allocator,
    .io = init.io,
});
```

### User Data Directory

Persist browser data between sessions:

```zig
var browser = try cdp.Browser.launch(.{
    .user_data_dir = "/path/to/profile",
    .allocator = allocator,
    .io = init.io,
});
```

### Debug Port

```zig
// Specific port
var browser = try cdp.Browser.launch(.{
    .port = 9222,
    .allocator = allocator,
    .io = init.io,
});

// Random available port (default)
var browser = try cdp.Browser.launch(.{
    .port = 0, // auto-assigned
    .allocator = allocator,
    .io = init.io,
});
```

### Security Options

```zig
var browser = try cdp.Browser.launch(.{
    .ignore_certificate_errors = true, // Skip HTTPS errors
    .no_sandbox = true,                // Required in containers
    .disable_gpu = true,               // Recommended for headless
    .allocator = allocator,
    .io = init.io,
});
```

### Extra Arguments

Pass additional Chrome flags:

```zig
var browser = try cdp.Browser.launch(.{
    .extra_args = &[_][]const u8{
        "--proxy-server=localhost:8080",
        "--disable-web-security",
        "--lang=en-US",
    },
    .allocator = allocator,
    .io = init.io,
});
```

## Connecting to Existing Chrome

### Start Chrome with Debugging

```bash
# Windows
chrome.exe --remote-debugging-port=9222

# macOS
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222

# Linux
google-chrome --remote-debugging-port=9222
```

### Connect

```zig
var browser = try cdp.Browser.connect(
    "ws://127.0.0.1:9222/devtools/browser/abc123",
    allocator,
    init.io,
);
defer browser.close();
```

::: tip
Get the WebSocket URL from `http://127.0.0.1:9222/json/version`
:::

## Browser Information

### Version Info

```zig
var version = try browser.version();
defer version.deinit(allocator);

std.debug.print("Protocol: {s}\n", .{version.protocol_version});
std.debug.print("Product: {s}\n", .{version.product});
std.debug.print("Revision: {s}\n", .{version.revision});
std.debug.print("User Agent: {s}\n", .{version.user_agent});
std.debug.print("JS Version: {s}\n", .{version.js_version});
```

### WebSocket URL

```zig
const ws_url = browser.getWsUrl();
std.debug.print("WebSocket URL: {s}\n", .{ws_url});
```

## Page Management

### Create New Page

```zig
var session = try browser.newPage();
defer session.detach() catch {};
```

### List All Pages

```zig
const pages = try browser.pages();
defer {
    for (pages) |*p| {
        p.deinit(allocator);
    }
    allocator.free(pages);
}

for (pages) |p| {
    std.debug.print("{s}: {s}\n", .{p.target_id, p.title});
}
```

### Close Page

```zig
try browser.closePage(target_id);
```

## Cleanup

Always close the browser when done:

```zig
var browser = try cdp.Browser.launch(.{ ... });
defer browser.close(); // Sends Browser.close, closes connection, terminates process
```

The `close()` method:
1. Sends `Browser.close` CDP command
2. Closes the WebSocket connection
3. Terminates the Chrome process (if launched)
4. Cleans up temp directories

## Error Handling

```zig
var browser = cdp.Browser.launch(.{ ... }) catch |err| switch (err) {
    error.ChromeNotFound => {
        std.debug.print("Chrome not found. Install Chrome or specify path.\n", .{});
        return;
    },
    error.LaunchFailed => {
        std.debug.print("Failed to start Chrome process.\n", .{});
        return;
    },
    error.StartupTimeout => {
        std.debug.print("Chrome didn't start in time.\n", .{});
        return;
    },
    else => return err,
};
```

## Chrome Auto-Discovery

zchrome searches these paths automatically:

### Windows
- `C:\Program Files\Google\Chrome\Application\chrome.exe`
- `C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`
- `C:\Program Files\Chromium\Application\chrome.exe`

### macOS
- `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`
- `/Applications/Chromium.app/Contents/MacOS/Chromium`

### Linux
- `/usr/bin/google-chrome`
- `/usr/bin/google-chrome-stable`
- `/usr/bin/chromium`
- `/usr/bin/chromium-browser`
- `/snap/bin/chromium`
