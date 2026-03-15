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
pub fn getDocument(self: *DOM, allocator: Allocator, options: GetDocumentOptions) !Node
```

**Options:**

| Field | Type | Description |
|-------|------|-------------|
| `depth` | `?i32` | Maximum depth of children to return (null = all) |
| `pierce` | `bool` | Whether to pierce shadow DOM and include shadow roots (default: false) |

**Returns:** `Node` (caller must deinit)

**Example:**

```zig
// Basic usage
const doc = try dom.getDocument(allocator, .{ .depth = 1 });
defer {
    var d = doc;
    d.deinit(allocator);
}
std.debug.print("Document node ID: {}\n", .{doc.node_id});

// With shadow DOM piercing
const full_doc = try dom.getDocument(allocator, .{ .depth = -1, .pierce = true });
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

### setFileInputFiles

Set files for a file input element. Used for file uploads.

```zig
pub fn setFileInputFiles(self: *DOM, node_id: i64, files: []const []const u8) !void
```

**Parameters:**
- `node_id` - Node ID of the file input element
- `files` - Array of absolute file paths

**Note:** File paths must be absolute paths on the local filesystem. This method only sets the files on the input element - it does not submit any form.

**Example:**

```zig
const file_input_id = try dom.querySelector(doc.node_id, "input[type=file]");
try dom.setFileInputFiles(file_input_id, &[_][]const u8{
    "/path/to/document.pdf",
    "/path/to/image.png",
});
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

### describeNode

Get detailed information about a node, including shadow roots and content documents.

```zig
pub fn describeNode(self: *DOM, allocator: Allocator, options: DescribeNodeOptions) !NodeDescription
```

**Options:**

| Field | Type | Description |
|-------|------|-------------|
| `node_id` | `?i64` | Node ID to describe |
| `backend_node_id` | `?i64` | Backend node ID |
| `object_id` | `?[]const u8` | Remote object ID |
| `depth` | `?i32` | Maximum depth (-1 for entire subtree) |
| `pierce` | `bool` | Whether to pierce shadow DOM (default: false) |

**Returns:** `NodeDescription` (caller must deinit)

**Example:**

```zig
var desc = try dom.describeNode(allocator, .{
    .node_id = element_id,
    .depth = 1,
    .pierce = true,
});
defer desc.deinit(allocator);

// Check shadow root type
if (desc.shadow_root_type) |srt| {
    switch (srt) {
        .open => std.debug.print("Open shadow root\n", .{}),
        .closed => std.debug.print("Closed shadow root\n", .{}),
        .user_agent => std.debug.print("User-agent shadow root\n", .{}),
    }
}

// Access shadow roots
if (desc.shadow_roots) |roots| {
    for (roots) |root| {
        std.debug.print("Shadow root node: {}\n", .{root.node_id});
    }
}
```

### getShadowRoot

Get the shadow root of a node (if it has one). This is a convenience wrapper around `describeNode`.

```zig
pub fn getShadowRoot(self: *DOM, allocator: Allocator, node_id: i64) !?NodeDescription
```

**Returns:** `?NodeDescription` - The shadow root, or null if the node has no shadow root.

**Example:**

```zig
if (try dom.getShadowRoot(allocator, host_node_id)) |shadow| {
    defer {
        var s = shadow;
        s.deinit(allocator);
    }
    // Query within shadow root
    const inner_id = try dom.querySelector(shadow.node_id, ".inner-element");
}
```

### requestNode

Get a node ID from a remote object ID.

```zig
pub fn requestNode(self: *DOM, object_id: []const u8) !i64
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

### ShadowRootType

```zig
pub const ShadowRootType = enum {
    user_agent,  // Browser internal shadow DOM (e.g., <input>, <video>)
    open,        // Accessible via element.shadowRoot
    closed,      // Not accessible via JavaScript
};
```

### NodeDescription

Detailed node information returned by `describeNode`.

```zig
pub const NodeDescription = struct {
    node_id: i64,
    backend_node_id: i64,
    node_type: i64,
    node_name: []const u8,
    local_name: ?[]const u8 = null,
    node_value: []const u8,
    frame_id: ?[]const u8 = null,
    /// Shadow root type (if this is a shadow root)
    shadow_root_type: ?ShadowRootType = null,
    /// Shadow roots of this element
    shadow_roots: ?[]NodeDescription = null,
    /// Content document for iframes
    content_document: ?*NodeDescription = null,

    pub fn deinit(self: *NodeDescription, allocator: Allocator) void;
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
