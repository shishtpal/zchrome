# DOM Manipulation

Query and modify the Document Object Model.

## Query Elements

### Single Element

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

    // Wait for load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Get document root
    const doc = try dom.getDocument(allocator, 1);
    defer {
        var d = doc;
        d.deinit(allocator);
    }

    // Find single element
    const h1_id = try dom.querySelector(doc.node_id, "h1");
    const h1_html = try dom.getOuterHTML(allocator, h1_id);
    defer allocator.free(h1_html);

    std.debug.print("H1: {s}\n", .{h1_html});
}
```

### Multiple Elements

```zig
// Find all links
const links = try dom.querySelectorAll(allocator, doc.node_id, "a[href]");
defer allocator.free(links);

std.debug.print("Found {} links\n", .{links.len});

for (links) |link_id| {
    const html = try dom.getOuterHTML(allocator, link_id);
    defer allocator.free(html);
    std.debug.print("  {s}\n", .{html});
}
```

## Get Element Content

### Outer HTML

```zig
const html = try dom.getOuterHTML(allocator, node_id);
defer allocator.free(html);
// Returns: <div class="content">Hello</div>
```

### Inner Text (via Runtime)

```zig
var runtime = cdp.Runtime.init(session);
try runtime.enable();

const text = try runtime.evaluateAs(
    []const u8,
    "document.querySelector('#content').innerText",
);
```

### Attributes

```zig
const attrs = try dom.getAttributes(allocator, node_id);
defer allocator.free(attrs);
// Returns flattened: "class container id main"
```

## Modify Elements

### Set Attribute

```zig
try dom.setAttributeValue(node_id, "class", "highlighted active");
try dom.setAttributeValue(node_id, "data-modified", "true");
```

### Remove Attribute

```zig
try dom.removeAttribute(node_id, "disabled");
```

### Replace HTML

```zig
try dom.setOuterHTML(node_id, "<div class=\"new\">New content</div>");
```

### Remove Element

```zig
try dom.removeNode(node_id);
```

## Focus Element

```zig
try dom.focus(node_id);
```

## Element Dimensions

```zig
const box = try dom.getBoxModel(allocator, node_id);

std.debug.print("Size: {}x{}\n", .{box.width, box.height});
std.debug.print("Position: ({d}, {d})\n", .{box.content[0], box.content[1]});
```

## Common Selectors

```zig
// By ID
const element = try dom.querySelector(doc.node_id, "#login-form");

// By class
const elements = try dom.querySelectorAll(allocator, doc.node_id, ".card");

// By tag
const divs = try dom.querySelectorAll(allocator, doc.node_id, "div");

// By attribute
const inputs = try dom.querySelectorAll(allocator, doc.node_id, "input[type='text']");

// Nested
const nested = try dom.querySelector(doc.node_id, "#form .submit-btn");

// Pseudo-selectors
const first = try dom.querySelector(doc.node_id, "li:first-child");
```

## Extract Data

### Extract All Links

```zig
const links = try dom.querySelectorAll(allocator, doc.node_id, "a[href]");
defer allocator.free(links);

var runtime = cdp.Runtime.init(session);
try runtime.enable();

for (links) |link_id| {
    const href = runtime.evaluateAs(
        []const u8,
        try std.fmt.allocPrint(allocator,
            "document.querySelector('[data-node-id=\"{}\"]')?.href",
            .{link_id}
        ),
    ) catch "N/A";
    
    std.debug.print("Link: {s}\n", .{href});
}
```

### Extract Table Data

```zig
const rows = try dom.querySelectorAll(allocator, doc.node_id, "table tbody tr");
defer allocator.free(rows);

for (rows) |row_id| {
    const cells = try dom.querySelectorAll(allocator, row_id, "td");
    defer allocator.free(cells);
    
    for (cells) |cell_id| {
        const html = try dom.getOuterHTML(allocator, cell_id);
        defer allocator.free(html);
        std.debug.print("{s}\t", .{html});
    }
    std.debug.print("\n", .{});
}
```

## Form Manipulation

### Fill Form Fields

```zig
var runtime = cdp.Runtime.init(session);
try runtime.enable();

// Set input values via JavaScript
_ = try runtime.evaluate(allocator,
    \\document.querySelector('#username').value = 'testuser';
    \\document.querySelector('#password').value = 'testpass';
, .{});

// Or use DOM + Input
const input_id = try dom.querySelector(doc.node_id, "#username");
try dom.focus(input_id);

var input = cdp.Input.init(session);
try input.type("testuser");
```

### Submit Form

```zig
_ = try runtime.evaluate(allocator,
    "document.querySelector('form').submit()",
    .{},
);
```

## Wait for Element

```zig
fn waitForElement(
    dom: *cdp.DOM,
    doc_id: i64,
    selector: []const u8,
    max_attempts: u32,
) !?i64 {
    var attempts: u32 = 0;
    while (attempts < max_attempts) : (attempts += 1) {
        if (dom.querySelector(doc_id, selector)) |node_id| {
            return node_id;
        } else |_| {
            // Wait and retry
            var i: u32 = 0;
            while (i < 100000) : (i += 1) {
                std.atomic.spinLoopHint();
            }
        }
    }
    return null;
}

// Usage
if (try waitForElement(&dom, doc.node_id, "#dynamic-content", 10)) |node_id| {
    const html = try dom.getOuterHTML(allocator, node_id);
    // ...
}
```

## Check Element Exists

```zig
const exists = dom.querySelector(doc.node_id, "#optional-element") catch null != null;

// Or via JavaScript
var runtime = cdp.Runtime.init(session);
const exists_js = try runtime.evaluateAs(
    bool,
    "document.querySelector('#optional-element') !== null",
);
```
