# Page Domain

The `Page` domain provides methods for navigation, screenshots, PDF generation, and page lifecycle management.

## Import

```zig
const cdp = @import("cdp");
const Page = cdp.Page;
```

## Initialization

```zig
var session = try browser.newPage();
var page = Page.init(session);
try page.enable();
```

## Methods

### enable / disable

Enable or disable the Page domain.

```zig
pub fn enable(self: *Page) !void
pub fn disable(self: *Page) !void
```

### navigate

Navigate to a URL.

```zig
pub fn navigate(self: *Page, allocator: Allocator, url: []const u8) !NavigateResult
```

**Returns:** `NavigateResult` (caller must deinit)

**Example:**

```zig
var result = try page.navigate(allocator, "https://example.com");
defer result.deinit(allocator);

if (result.error_text) |err| {
    std.debug.print("Navigation error: {s}\n", .{err});
}
```

### reload

Reload the current page.

```zig
pub fn reload(self: *Page, ignore_cache: ?bool) !void
```

**Example:**

```zig
try page.reload(true); // Ignore cache
```

### stopLoading

Stop page loading.

```zig
pub fn stopLoading(self: *Page) !void
```

### captureScreenshot

Capture a screenshot.

```zig
pub fn captureScreenshot(
    self: *Page,
    allocator: Allocator,
    params: CaptureScreenshotParams,
) ![]const u8
```

**Parameters:**

| Field | Type | Description |
|-------|------|-------------|
| `format` | `?ScreenshotFormat` | `.png`, `.jpeg`, `.webp` |
| `quality` | `?i32` | JPEG quality (0-100) |
| `clip` | `?Viewport` | Capture region |
| `from_surface` | `?bool` | Capture from surface |
| `capture_beyond_viewport` | `?bool` | Capture full page |

**Returns:** Base64-encoded image data

**Example:**

```zig
const screenshot = try page.captureScreenshot(allocator, .{
    .format = .png,
    .capture_beyond_viewport = true,
});
defer allocator.free(screenshot);

// Decode base64
const decoded = try cdp.base64.decodeAlloc(allocator, screenshot);
defer allocator.free(decoded);
```

### printToPDF

Generate PDF of the page.

```zig
pub fn printToPDF(
    self: *Page,
    allocator: Allocator,
    params: PrintToPDFParams,
) ![]const u8
```

**Parameters:**

| Field | Type | Description |
|-------|------|-------------|
| `landscape` | `?bool` | Landscape orientation |
| `print_background` | `?bool` | Print backgrounds |
| `scale` | `?f64` | Scale factor |
| `paper_width` | `?f64` | Width in inches |
| `paper_height` | `?f64` | Height in inches |
| `margin_top/bottom/left/right` | `?f64` | Margins in inches |
| `page_ranges` | `?[]const u8` | e.g., "1-5, 8" |
| `header_template` | `?[]const u8` | Header HTML |
| `footer_template` | `?[]const u8` | Footer HTML |

**Returns:** Base64-encoded PDF data

**Example:**

```zig
const pdf = try page.printToPDF(allocator, .{
    .landscape = false,
    .print_background = true,
    .margin_top = 0.5,
    .margin_bottom = 0.5,
});
defer allocator.free(pdf);
```

### getMainFrame

Get the main frame information.

```zig
pub fn getMainFrame(self: *Page, allocator: Allocator) !Frame
```

### setDocumentContent

Set the page HTML content.

```zig
pub fn setDocumentContent(self: *Page, html: []const u8) !void
```

**Example:**

```zig
try page.setDocumentContent("<html><body><h1>Hello</h1></body></html>");
```

### bringToFront

Bring the page to front.

```zig
pub fn bringToFront(self: *Page) !void
```

### setLifecycleEventsEnabled

Enable lifecycle events.

```zig
pub fn setLifecycleEventsEnabled(self: *Page, enabled: bool) !void
```

### addScriptToEvaluateOnNewDocument

Add script to run on every new document.

```zig
pub fn addScriptToEvaluateOnNewDocument(self: *Page, source: []const u8) ![]const u8
```

**Returns:** Script identifier

### removeScriptToEvaluateOnNewDocument

Remove an injected script.

```zig
pub fn removeScriptToEvaluateOnNewDocument(self: *Page, identifier: []const u8) !void
```

## Types

### NavigateResult

```zig
pub const NavigateResult = struct {
    frame_id: []const u8,
    loader_id: ?[]const u8 = null,
    error_text: ?[]const u8 = null,

    pub fn deinit(self: *NavigateResult, allocator: Allocator) void;
};
```

### ScreenshotFormat

```zig
pub const ScreenshotFormat = enum {
    jpeg,
    png,
    webp,
};
```

### Viewport

```zig
pub const Viewport = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    scale: f64 = 1.0,
};
```

### Frame

```zig
pub const Frame = struct {
    id: []const u8,
    parent_id: ?[]const u8 = null,
    loader_id: []const u8,
    name: ?[]const u8 = null,
    url: []const u8,
    security_origin: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,

    pub fn deinit(self: *Frame, allocator: Allocator) void;
};
```

## Events

| Event | Description |
|-------|-------------|
| `LoadEventFired` | Page load completed |
| `DomContentEventFired` | DOM content loaded |
| `FrameNavigated` | Frame navigation completed |
| `FrameStartedLoading` | Frame started loading |
| `FrameStoppedLoading` | Frame stopped loading |
| `LifecycleEvent` | Lifecycle event fired |

## Complete Example

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

    // Navigate
    var result = try page.navigate(allocator, "https://example.com");
    defer result.deinit(allocator);

    // Wait for load (simplified)
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Screenshot
    const screenshot = try page.captureScreenshot(allocator, .{ .format = .png });
    defer allocator.free(screenshot);

    // PDF
    const pdf = try page.printToPDF(allocator, .{ .print_background = true });
    defer allocator.free(pdf);

    std.debug.print("Screenshot: {} bytes, PDF: {} bytes\n", .{
        screenshot.len, pdf.len,
    });
}
```
