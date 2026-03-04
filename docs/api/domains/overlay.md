# Overlay Domain

The Overlay domain provides methods for highlighting DOM elements and showing debug overlays.

## Usage

```zig
const cdp = @import("cdp");

var overlay = cdp.Overlay.init(&session);
```

## Methods

### enable / disable

Enable or disable the overlay domain.

```zig
pub fn enable(self: *Self) !void
pub fn disable(self: *Self) !void
```

### hideHighlight

Hide any visible highlight.

```zig
pub fn hideHighlight(self: *Self) !void
```

### highlightNode

Highlight a DOM node with customizable colors.

```zig
pub fn highlightNode(
    self: *Self,
    config: HighlightConfig,
    node_id: ?i64,
    backend_node_id: ?i64,
    object_id: ?[]const u8,
    selector: ?[]const u8
) !void
```

**Example:**

```zig
try overlay.enable();

// Highlight by selector
try overlay.highlightNode(
    cdp.HighlightConfig.default(),
    null, null, null,
    "#login-button"
);

// Hide after delay
std.time.sleep(3 * std.time.ns_per_s);
try overlay.hideHighlight();
```

### highlightQuad

Highlight an arbitrary quadrilateral.

```zig
pub fn highlightQuad(
    self: *Self,
    quad: [8]f64,
    color: ?RGBA,
    outline_color: ?RGBA
) !void
```

### highlightRect

Highlight a rectangular area.

```zig
pub fn highlightRect(
    self: *Self,
    x: i32, y: i32,
    width: i32, height: i32,
    color: ?RGBA,
    outline_color: ?RGBA
) !void
```

**Example:**

```zig
try overlay.highlightRect(
    100, 200, 300, 50,
    cdp.RGBA.rgba(255, 0, 0, 0.5),
    cdp.RGBA.rgba(255, 0, 0, 1.0)
);
```

### setInspectMode

Set the inspect mode for element selection.

```zig
pub fn setInspectMode(self: *Self, mode: []const u8, config: ?HighlightConfig) !void
```

**Modes:**
- `"none"` - Disable inspect mode
- `"searchForNode"` - Enable node search
- `"searchForUAShadowDOM"` - Search including UA shadow DOM
- `"captureAreaScreenshot"` - Capture area selection mode

### Debug Overlays

```zig
pub fn setShowDebugBorders(self: *Self, show: bool) !void
pub fn setShowFPSCounter(self: *Self, show: bool) !void
pub fn setShowPaintRects(self: *Self, result: bool) !void
pub fn setShowViewportSizeOnResize(self: *Self, show: bool) !void
```

**Example:**

```zig
// Show debug borders around all elements
try overlay.setShowDebugBorders(true);

// Show FPS counter
try overlay.setShowFPSCounter(true);

// Show paint rectangles during repaints
try overlay.setShowPaintRects(true);
```

## Types

### RGBA

Color with red, green, blue, and alpha components.

```zig
pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: ?f64 = null,

    pub fn fromHex(hex: u32) RGBA
    pub fn rgba(r: u8, g: u8, b: u8, a: f64) RGBA

    // Predefined colors
    pub const content_default = RGBA.rgba(111, 168, 220, 0.66);
    pub const padding_default = RGBA.rgba(147, 196, 125, 0.55);
    pub const border_default = RGBA.rgba(255, 229, 153, 0.66);
    pub const margin_default = RGBA.rgba(246, 178, 107, 0.66);
};
```

### HighlightConfig

Configuration for element highlighting.

```zig
pub const HighlightConfig = struct {
    show_info: ?bool = null,
    show_styles: ?bool = null,
    show_rulers: ?bool = null,
    show_accessibility_info: ?bool = null,
    show_extension_lines: ?bool = null,
    content_color: ?RGBA = null,
    padding_color: ?RGBA = null,
    border_color: ?RGBA = null,
    margin_color: ?RGBA = null,

    pub fn default() HighlightConfig {
        return .{
            .show_info = true,
            .content_color = RGBA.content_default,
            .padding_color = RGBA.padding_default,
            .border_color = RGBA.border_default,
            .margin_color = RGBA.margin_default,
        };
    }
};
```

## CLI Usage

The `dev highlight` command uses JavaScript-based highlighting for simplicity:

```bash
zchrome dev highlight "#login-btn"
# Highlighted: button#login-btn

zchrome dev highlight ".header"
# Highlighted: header.main-header
```

The highlight appears for 3 seconds with a blue semi-transparent overlay.

## DevTools-Style Highlighting

For DevTools-style box model highlighting:

```zig
try overlay.enable();
try overlay.highlightNode(
    .{
        .show_info = true,
        .show_rulers = true,
        .content_color = cdp.RGBA.content_default,
        .padding_color = cdp.RGBA.padding_default,
        .border_color = cdp.RGBA.border_default,
        .margin_color = cdp.RGBA.margin_default,
    },
    null, null, null, "#myElement"
);
```
