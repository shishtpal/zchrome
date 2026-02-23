# Examples

This section contains practical examples demonstrating common use cases for zchrome.

## Quick Reference

| Example | Description |
|---------|-------------|
| [Screenshots](/examples/screenshots) | Capture full-page and element screenshots |
| [PDF Generation](/examples/pdf) | Generate PDFs from web pages |
| [DOM Manipulation](/examples/dom) | Query and modify the DOM |
| [JavaScript Evaluation](/examples/javascript) | Execute JavaScript and get results |
| [Network Interception](/examples/network) | Monitor and modify network traffic |
| [Browser Interactions](/examples/interactions) | Click, type, fill forms using CLI |
| [Macro Recording](/examples/macros) | Record and replay browser interactions |

## Basic Pattern

Most zchrome scripts follow this pattern:

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // 1. Launch browser
    var browser = try cdp.Browser.launch(.{
        .headless = .new,
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    // 2. Create page/session
    var session = try browser.newPage();
    defer session.detach() catch {};

    // 3. Initialize domain clients
    var page = cdp.Page.init(session);
    try page.enable();

    // 4. Navigate
    _ = try page.navigate(allocator, "https://example.com");

    // 5. Wait for content (simplified)
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // 6. Perform operations
    // ...
}
```

## Running Examples

To run examples in this guide:

1. **Create a new Zig project:**
   ```bash
   mkdir my-scraper
   cd my-scraper
   zig init
   ```

2. **Add zchrome dependency** to `build.zig.zon`:
   ```zig
   .dependencies = .{
       .cdp = .{
           .path = "../zchrome",
       },
   },
   ```

3. **Configure build.zig:**
   ```zig
   const cdp = b.dependency("cdp", .{
       .target = target,
       .optimize = optimize,
   });
   exe.root_module.addImport("cdp", cdp.module("cdp"));
   ```

4. **Build and run:**
   ```bash
   zig build run
   ```

## Tips

### Waiting for Page Load

The examples use a simple spin-loop for waiting. In production:

```zig
// Simple approach (examples)
var i: u32 = 0;
while (i < 500000) : (i += 1) {
    std.atomic.spinLoopHint();
}

// Better: Use lifecycle events
try page.setLifecycleEventsEnabled(true);
// Listen for "load" or "networkIdle" events
```

### Error Handling

Always check for navigation errors:

```zig
var result = try page.navigate(allocator, url);
defer result.deinit(allocator);

if (result.error_text) |err| {
    std.debug.print("Failed: {s}\n", .{err});
    return;
}
```

### Resource Cleanup

Use `defer` consistently:

```zig
var browser = try cdp.Browser.launch(.{ ... });
defer browser.close();

var session = try browser.newPage();
defer session.detach() catch {};

const data = try allocate();
defer allocator.free(data);
```

### Multiple Pages

For parallel scraping:

```zig
var sessions: [4]*cdp.Session = undefined;
for (&sessions) |*s| {
    s.* = try browser.newPage();
}
defer for (sessions) |s| {
    s.detach() catch {};
};

// Use each session for different URLs
```
