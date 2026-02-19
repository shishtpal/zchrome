# Input Domain

The `Input` domain provides methods for simulating mouse and keyboard input.

## Import

```zig
const cdp = @import("cdp");
const Input = cdp.Input;
```

## Initialization

```zig
var session = try browser.newPage();
var input = Input.init(session);
```

## Mouse Methods

### dispatchMouseEvent

Dispatch a mouse event.

```zig
pub fn dispatchMouseEvent(
    self: *Input,
    event_type: MouseEventType,
    x: f64,
    y: f64,
    options: MouseEventOptions,
) !void
```

**Event Types:**

```zig
pub const MouseEventType = enum {
    mousePressed,
    mouseReleased,
    mouseMoved,
    mouseWheel,
};
```

**Options:**

| Field | Type | Description |
|-------|------|-------------|
| `button` | `?MouseButton` | `.left`, `.middle`, `.right` |
| `buttons` | `?i32` | Button mask |
| `click_count` | `?i32` | Click count |
| `delta_x` | `?f64` | Wheel delta X |
| `delta_y` | `?f64` | Wheel delta Y |
| `modifiers` | `?i32` | Alt=1, Ctrl=2, Meta=4, Shift=8 |

### click

Convenience method for clicking.

```zig
pub fn click(self: *Input, x: f64, y: f64, options: ClickOptions) !void
```

**Example:**

```zig
try input.click(100, 200, .{
    .button = .left,
    .click_count = 1,
});
```

### doubleClick

Double-click at coordinates.

```zig
pub fn doubleClick(self: *Input, x: f64, y: f64) !void
```

### moveTo

Move mouse to coordinates.

```zig
pub fn moveTo(self: *Input, x: f64, y: f64) !void
```

### scroll

Scroll by delta.

```zig
pub fn scroll(self: *Input, x: f64, y: f64, delta_x: f64, delta_y: f64) !void
```

## Keyboard Methods

### dispatchKeyEvent

Dispatch a keyboard event.

```zig
pub fn dispatchKeyEvent(
    self: *Input,
    event_type: KeyEventType,
    options: KeyEventOptions,
) !void
```

**Event Types:**

```zig
pub const KeyEventType = enum {
    keyDown,
    keyUp,
    rawKeyDown,
    char,
};
```

**Options:**

| Field | Type | Description |
|-------|------|-------------|
| `key` | `?[]const u8` | Key value ("Enter", "a", etc.) |
| `code` | `?[]const u8` | Physical key code |
| `text` | `?[]const u8` | Text to input |
| `modifiers` | `?i32` | Modifier mask |
| `windows_virtual_key_code` | `?i32` | Windows VK code |

### type

Type text character by character.

```zig
pub fn type(self: *Input, text: []const u8) !void
```

**Example:**

```zig
try input.type("Hello, World!");
```

### press

Press and release a key.

```zig
pub fn press(self: *Input, key: []const u8) !void
```

**Example:**

```zig
try input.press("Enter");
try input.press("Tab");
try input.press("Escape");
```

### keyDown / keyUp

Press or release a key.

```zig
pub fn keyDown(self: *Input, key: []const u8, modifiers: ?i32) !void
pub fn keyUp(self: *Input, key: []const u8, modifiers: ?i32) !void
```

## Common Key Names

| Key | Name |
|-----|------|
| Enter | `"Enter"` |
| Tab | `"Tab"` |
| Escape | `"Escape"` |
| Backspace | `"Backspace"` |
| Delete | `"Delete"` |
| Arrow keys | `"ArrowUp"`, `"ArrowDown"`, `"ArrowLeft"`, `"ArrowRight"` |
| Home/End | `"Home"`, `"End"` |
| Page Up/Down | `"PageUp"`, `"PageDown"` |

## Modifier Masks

Combine with bitwise OR:

| Modifier | Value |
|----------|-------|
| Alt | 1 |
| Ctrl | 2 |
| Meta (Cmd) | 4 |
| Shift | 8 |

**Example:**

```zig
// Ctrl+A (Select All)
try input.keyDown("a", 2); // Ctrl=2
try input.keyUp("a", 2);

// Ctrl+Shift+S
try input.keyDown("s", 2 | 8); // Ctrl+Shift
try input.keyUp("s", 2 | 8);
```

## Complete Example

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var browser = try cdp.Browser.launch(.{
        .headless = .off, // Visible for demo
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    var dom = cdp.DOM.init(session);
    var input = cdp.Input.init(session);
    
    try page.enable();
    try dom.enable();

    _ = try page.navigate(allocator, "https://www.google.com");
    
    // Wait for load
    var i: u32 = 0;
    while (i < 1000000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Find search box and get its position
    const doc = try dom.getDocument(allocator, 1);
    const search_id = try dom.querySelector(doc.node_id, "textarea[name='q']");
    const box = try dom.getBoxModel(allocator, search_id);
    
    // Calculate center of element
    const x = @as(f64, @floatFromInt(box.content[0])) + @as(f64, @floatFromInt(box.width)) / 2;
    const y = @as(f64, @floatFromInt(box.content[1])) + @as(f64, @floatFromInt(box.height)) / 2;

    // Click on search box
    try input.click(x, y, .{});

    // Type search query
    try input.type("zchrome zig cdp");

    // Press Enter
    try input.press("Enter");
}
```
