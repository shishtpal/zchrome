# Screenshots

Capture screenshots of web pages in various formats and configurations.

## Basic Screenshot

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
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, "https://example.com");

    // Wait for load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Capture PNG screenshot
    const screenshot = try page.captureScreenshot(allocator, .{
        .format = .png,
    });
    defer allocator.free(screenshot);

    // Decode base64
    const decoded = try cdp.base64.decodeAlloc(allocator, screenshot);
    defer allocator.free(decoded);

    std.debug.print("Screenshot: {} bytes\n", .{decoded.len});
}
```

## Format Options

### PNG (Lossless)

```zig
const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
});
```

### JPEG (Lossy, smaller)

```zig
const screenshot = try page.captureScreenshot(allocator, .{
    .format = .jpeg,
    .quality = 80, // 0-100
});
```

### WebP (Modern, efficient)

```zig
const screenshot = try page.captureScreenshot(allocator, .{
    .format = .webp,
    .quality = 80,
});
```

## Full Page Screenshot

Capture content beyond the viewport:

```zig
const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
    .capture_beyond_viewport = true,
});
```

## Element Screenshot

Capture a specific element:

```zig
var dom = cdp.DOM.init(session);
try dom.enable();

// Get document and find element
const doc = try dom.getDocument(allocator, 1);
const element_id = try dom.querySelector(doc.node_id, "#main-content");

// Get element bounding box
const box = try dom.getBoxModel(allocator, element_id);

// Capture with clip
const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
    .clip = .{
        .x = box.content[0],
        .y = box.content[1],
        .width = @floatFromInt(box.width),
        .height = @floatFromInt(box.height),
        .scale = 1.0,
    },
});
```

## High DPI Screenshot

Capture at higher resolution:

```zig
var emulation = cdp.Emulation.init(session);

// Set device scale factor
try emulation.setDeviceMetricsOverride(
    1920, // width
    1080, // height
    2.0,  // device scale factor (2x = retina)
    false,
);

const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
});
```

## Mobile Screenshot

Emulate mobile device before capturing:

```zig
var emulation = cdp.Emulation.init(session);

// iPhone 12 Pro
try emulation.setDeviceMetricsOverride(390, 844, 3, true);
try emulation.setUserAgentOverride(
    "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)",
    "en-US",
    "iPhone",
);

_ = try page.navigate(allocator, "https://example.com");

const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
});
```

## Screenshot with Custom Viewport

```zig
var emulation = cdp.Emulation.init(session);

// Set specific viewport
try emulation.setDeviceMetricsOverride(
    1200,  // width
    800,   // height
    1.0,   // scale
    false, // mobile
);

_ = try page.navigate(allocator, "https://example.com");

const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
});
```

## Multiple Screenshots

Capture multiple pages:

```zig
const urls = [_][]const u8{
    "https://example.com",
    "https://google.com",
    "https://github.com",
};

for (urls, 0..) |url, idx| {
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, url);

    // Wait
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    const screenshot = try page.captureScreenshot(allocator, .{
        .format = .png,
    });
    defer allocator.free(screenshot);

    std.debug.print("Screenshot {}: {} bytes\n", .{idx, screenshot.len});
}
```

## Dark Mode Screenshot

```zig
var emulation = cdp.Emulation.init(session);

// Emulate dark mode preference
try emulation.setEmulatedMedia(null, &[_]MediaFeature{
    .{ .name = "prefers-color-scheme", .value = "dark" },
});

_ = try page.navigate(allocator, "https://example.com");

const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
});
```

## Print-Style Screenshot

```zig
var emulation = cdp.Emulation.init(session);

// Emulate print media
try emulation.setEmulatedMedia("print", null);

_ = try page.navigate(allocator, "https://example.com");

const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
});
```
