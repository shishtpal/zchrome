# CSS Domain

The `CSS` domain provides methods for stylesheet inspection and modification.

## Import

```zig
const cdp = @import("cdp");
const CSS = cdp.CSS;
```

## Initialization

```zig
var session = try browser.newPage();
var css = CSS.init(session);
try css.enable();
```

## Methods

### enable

Enable CSS domain events. Required before using other CSS methods.

```zig
pub fn enable(self: *CSS) !void
```

### disable

Disable CSS domain.

```zig
pub fn disable(self: *CSS) !void
```

### getStyleSheetText

Get the content of a stylesheet.

```zig
pub fn getStyleSheetText(
    self: *CSS,
    allocator: Allocator,
    style_sheet_id: StyleSheetId,
) ![]const u8
```

**Returns:** The stylesheet text content.

### setStyleSheetText

Replace the content of a stylesheet.

```zig
pub fn setStyleSheetText(
    self: *CSS,
    allocator: Allocator,
    style_sheet_id: StyleSheetId,
    text: []const u8,
) ![]const u8
```

**Returns:** Source map URL if available.

### getComputedStyleForNode

Get computed styles for a DOM node.

```zig
pub fn getComputedStyleForNode(
    self: *CSS,
    allocator: Allocator,
    node_id: i64,
) ![]CSSComputedStyleProperty
```

**Returns:** Array of computed style properties.

### createStyleSheet

Create a new stylesheet in a frame.

```zig
pub fn createStyleSheet(
    self: *CSS,
    allocator: Allocator,
    frame_id: []const u8,
) !StyleSheetId
```

**Returns:** The new stylesheet's ID.

### addRule

Add a CSS rule to a stylesheet.

```zig
pub fn addRule(
    self: *CSS,
    allocator: Allocator,
    style_sheet_id: StyleSheetId,
    rule_text: []const u8,
    location: SourceRange,
) !json.Value
```

### forcePseudoState

Force pseudo states on an element (e.g., `:hover`, `:active`, `:focus`).

```zig
pub fn forcePseudoState(
    self: *CSS,
    node_id: i64,
    forced_pseudo_classes: []const []const u8,
) !void
```

### getMatchedStylesForNode

Get matched CSS rules for a node.

```zig
pub fn getMatchedStylesForNode(self: *CSS, node_id: i64) !json.Value
```

### getInlineStylesForNode

Get inline styles for a node.

```zig
pub fn getInlineStylesForNode(self: *CSS, node_id: i64) !json.Value
```

## Types

### StyleSheetOrigin

```zig
pub const StyleSheetOrigin = enum {
    injected,
    user_agent,
    inspector,
    regular,
};
```

### CSSStyleSheetHeader

```zig
pub const CSSStyleSheetHeader = struct {
    style_sheet_id: StyleSheetId,
    frame_id: []const u8,
    source_url: []const u8,
    origin: StyleSheetOrigin,
    title: []const u8,
    disabled: bool,
    is_inline: bool,
    // ... additional fields
};
```

### CSSComputedStyleProperty

```zig
pub const CSSComputedStyleProperty = struct {
    name: []const u8,
    value: []const u8,
};
```

### SourceRange

```zig
pub const SourceRange = struct {
    start_line: i64,
    start_column: i64,
    end_line: i64,
    end_column: i64,
};
```

## Events

### styleSheetAdded

Fired when a stylesheet is added.

### styleSheetChanged

Fired when stylesheet content changes.

### styleSheetRemoved

Fired when a stylesheet is removed.

## Example

```zig
const cdp = @import("cdp");

pub fn inspectStyles(session: *cdp.Session, allocator: Allocator) !void {
    var css = cdp.CSS.init(session);
    try css.enable();

    var dom = cdp.DOM.init(session);
    try dom.enable();
    
    const doc = try dom.getDocument(allocator, .{});
    defer {
        var d = doc;
        d.deinit(allocator);
    }

    // Get computed styles for body
    const body_id = try dom.querySelector(doc.node_id, "body");
    const styles = try css.getComputedStyleForNode(allocator, body_id);
    defer {
        for (styles) |*s| s.deinit(allocator);
        allocator.free(styles);
    }

    for (styles) |style| {
        std.debug.print("{s}: {s}\n", .{ style.name, style.value });
    }
}
```
