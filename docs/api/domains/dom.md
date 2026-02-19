# DOM Domain

The `DOM` domain provides methods for querying and manipulating the Document Object Model.

## Import

```zig
const cdp = @import("cdp");
const DOM = cdp.DOM;
```

## Initialization

```zig
var session = try browser.newPage();
var dom = DOM.init(session);
try dom.enable();
```

## Methods

### enable / disable

Enable or disable the DOM domain.

```zig
pub fn enable(self: *DOM) !void
pub fn disable(self: *DOM) !void
```

### getDocument

Get the document root node.

```zig
pub fn getDocument(self: *DOM, allocator: Allocator, depth: ?i32) !Node
```

**Parameters:**
- `depth` - Maximum depth of children to return (null = all)

**Returns:** `Node` (caller must deinit)

**Example:**

```zig
const doc = try dom.getDocument(allocator, 1);
defer {
    var d = doc;
    d.deinit(allocator);
}
std.debug.print("Document node ID: {}\n", .{doc.node_id});
```

### querySelector

Find a single element matching a CSS selector.

```zig
pub fn querySelector(self: *DOM, node_id: i64, selector: []const u8) !i64
```

**Parameters:**
- `node_id` - Starting node ID (usually document node)
- `selector` - CSS selector

**Returns:** Node ID of matching element

**Example:**

```zig
const doc = try dom.getDocument(allocator, 1);
const h1_id = try dom.querySelector(doc.node_id, "h1");
```

### querySelectorAll

Find all elements matching a CSS selector.

```zig
pub fn querySelectorAll(
    self: *DOM,
    allocator: Allocator,
    node_id: i64,
    selector: []const u8,
) ![]i64
```

**Returns:** Slice of node IDs (caller must free)

**Example:**

```zig
const links = try dom.querySelectorAll(allocator, doc.node_id, "a");
defer allocator.free(links);

for (links) |link_id| {
    const href = try dom.getAttributes(allocator, link_id);
    defer allocator.free(href);
}
```

### getOuterHTML

Get the outer HTML of an element.

```zig
pub fn getOuterHTML(self: *DOM, allocator: Allocator, node_id: i64) ![]const u8
```

**Returns:** HTML string (caller must free)

**Example:**

```zig
const html = try dom.getOuterHTML(allocator, node_id);
defer allocator.free(html);
std.debug.print("HTML: {s}\n", .{html});
```

### setOuterHTML

Replace an element's outer HTML.

```zig
pub fn setOuterHTML(self: *DOM, node_id: i64, outer_html: []const u8) !void
```

**Example:**

```zig
try dom.setOuterHTML(node_id, "<div class=\"new\">Updated content</div>");
```

### getAttributes

Get element attributes.

```zig
pub fn getAttributes(self: *DOM, allocator: Allocator, node_id: i64) ![]const u8
```

**Returns:** Flattened attribute string

### setAttributeValue

Set an attribute value.

```zig
pub fn setAttributeValue(self: *DOM, node_id: i64, name: []const u8, value: []const u8) !void
```

**Example:**

```zig
try dom.setAttributeValue(node_id, "class", "highlighted");
```

### removeAttribute

Remove an attribute.

```zig
pub fn removeAttribute(self: *DOM, node_id: i64, name: []const u8) !void
```

### removeNode

Remove a node from the DOM.

```zig
pub fn removeNode(self: *DOM, node_id: i64) !void
```

### focus

Focus an element.

```zig
pub fn focus(self: *DOM, node_id: i64) !void
```

### getBoxModel

Get element's box model dimensions.

```zig
pub fn getBoxModel(self: *DOM, allocator: Allocator, node_id: i64) !BoxModel
```

**Returns:** `BoxModel` with content, padding, border, margin quads

### resolveNode

Resolve a node to a Runtime remote object.

```zig
pub fn resolveNode(self: *DOM, allocator: Allocator, node_id: i64) !RemoteObject
```

## Types

### Node

```zig
pub const Node = struct {
    node_id: i64,
    node_type: i64,          // 1=Element, 3=Text, 9=Document, etc.
    node_name: []const u8,   // Tag name or #text, #document
    node_value: []const u8,  // Text content or empty
    children: ?[]Node = null,
    attributes: ?[]const u8 = null,
    document_url: ?[]const u8 = null,
    base_url: ?[]const u8 = null,

    pub fn deinit(self: *Node, allocator: Allocator) void;
};
```

### BoxModel

```zig
pub const BoxModel = struct {
    content: [8]f64,  // 4 corners × 2 coordinates
    padding: [8]f64,
    border: [8]f64,
    margin: [8]f64,
    width: i64,
    height: i64,
};
```

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
    var dom = cdp.DOM.init(session);
    
    try page.enable();
    try dom.enable();

    _ = try page.navigate(allocator, "https://example.com");
    
    // Wait for page load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Get document
    const doc = try dom.getDocument(allocator, 1);
    defer {
        var d = doc;
        d.deinit(allocator);
    }

    // Find heading
    const h1_id = try dom.querySelector(doc.node_id, "h1");
    const h1_html = try dom.getOuterHTML(allocator, h1_id);
    defer allocator.free(h1_html);

    std.debug.print("H1: {s}\n", .{h1_html});

    // Find all links
    const links = try dom.querySelectorAll(allocator, doc.node_id, "a[href]");
    defer allocator.free(links);

    std.debug.print("Found {} links\n", .{links.len});

    // Get box model
    const box = try dom.getBoxModel(allocator, h1_id);
    std.debug.print("H1 size: {}x{}\n", .{box.width, box.height});
}
```
