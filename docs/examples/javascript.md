# JavaScript Evaluation

Execute JavaScript in the browser context and retrieve results.

## Basic Evaluation

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
    var runtime = cdp.Runtime.init(session);
    
    try page.enable();
    try runtime.enable();

    _ = try page.navigate(allocator, "https://example.com");

    // Wait for load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Simple evaluation
    const result = try runtime.evaluateAs(i64, "1 + 2");
    std.debug.print("Result: {}\n", .{result}); // 3
}
```

## Return Types

### String

```zig
const title = try runtime.evaluateAs([]const u8, "document.title");
std.debug.print("Title: {s}\n", .{title});
```

### Number

```zig
const count = try runtime.evaluateAs(i64, "document.links.length");
std.debug.print("Links: {}\n", .{count});

const ratio = try runtime.evaluateAs(f64, "window.devicePixelRatio");
std.debug.print("DPR: {d}\n", .{ratio});
```

### Boolean

```zig
const visible = try runtime.evaluateAs(bool, "document.visibilityState === 'visible'");
std.debug.print("Visible: {}\n", .{visible});
```

### Complex Objects

```zig
var result = try runtime.evaluate(allocator,
    \\({
    \\  title: document.title,
    \\  url: location.href,
    \\  links: document.links.length
    \\})
, .{ .return_by_value = true });
defer result.deinit(allocator);

if (result.value) |v| {
    // v is std.json.Value
}
```

## Page Information

```zig
// URL
const url = try runtime.evaluateAs([]const u8, "location.href");

// Title
const title = try runtime.evaluateAs([]const u8, "document.title");

// Document ready state
const ready = try runtime.evaluateAs([]const u8, "document.readyState");

// Viewport size
const width = try runtime.evaluateAs(i64, "window.innerWidth");
const height = try runtime.evaluateAs(i64, "window.innerHeight");

// Scroll position
const scroll_x = try runtime.evaluateAs(i64, "window.scrollX");
const scroll_y = try runtime.evaluateAs(i64, "window.scrollY");
```

## DOM Queries

```zig
// Element text
const heading = try runtime.evaluateAs(
    []const u8,
    "document.querySelector('h1')?.innerText || 'Not found'",
);

// Element count
const count = try runtime.evaluateAs(
    i64,
    "document.querySelectorAll('.item').length",
);

// Check existence
const exists = try runtime.evaluateAs(
    bool,
    "document.querySelector('#login-form') !== null",
);

// Get attribute
const href = try runtime.evaluateAs(
    []const u8,
    "document.querySelector('a.primary')?.href || ''",
);
```

## Modify Page

```zig
// Set value
_ = try runtime.evaluate(allocator,
    "document.querySelector('#search').value = 'hello'",
    .{},
);

// Click button
_ = try runtime.evaluate(allocator,
    "document.querySelector('#submit-btn').click()",
    .{},
);

// Scroll to element
_ = try runtime.evaluate(allocator,
    "document.querySelector('#footer').scrollIntoView()",
    .{},
);

// Add class
_ = try runtime.evaluate(allocator,
    "document.body.classList.add('loaded')",
    .{},
);
```

## Extract Data

### Extract Links

```zig
var result = try runtime.evaluate(allocator,
    \\Array.from(document.querySelectorAll('a[href]')).map(a => ({
    \\  text: a.innerText.trim(),
    \\  href: a.href
    \\}))
, .{ .return_by_value = true });
defer result.deinit(allocator);
```

### Extract Table

```zig
var result = try runtime.evaluate(allocator,
    \\Array.from(document.querySelectorAll('table tr')).map(row =>
    \\  Array.from(row.querySelectorAll('td, th')).map(cell => cell.innerText.trim())
    \\)
, .{ .return_by_value = true });
defer result.deinit(allocator);
```

### Extract Form Data

```zig
var result = try runtime.evaluate(allocator,
    \\Object.fromEntries(
    \\  new FormData(document.querySelector('form'))
    \\)
, .{ .return_by_value = true });
defer result.deinit(allocator);
```

## Async Functions

### Await Promise

```zig
var result = try runtime.evaluate(allocator,
    \\fetch('/api/data').then(r => r.json())
, .{
    .await_promise = true,
    .return_by_value = true,
});
defer result.deinit(allocator);
```

### Custom Async

```zig
var result = try runtime.evaluate(allocator,
    \\new Promise(resolve => {
    \\  setTimeout(() => resolve('done'), 1000);
    \\})
, .{ .await_promise = true });
defer result.deinit(allocator);
```

## Error Handling

```zig
var result = try runtime.evaluate(allocator,
    "nonExistent.property",
    .{},
);
defer result.deinit(allocator);

if (result.exception_details) |exception| {
    std.debug.print("Error: {s}\n", .{exception.text});
    return;
}
```

## Inject Script

```zig
// Add script to run on every new document
const script_id = try page.addScriptToEvaluateOnNewDocument(
    \\Object.defineProperty(navigator, 'webdriver', {
    \\  get: () => false
    \\});
);

// Later: remove if needed
try page.removeScriptToEvaluateOnNewDocument(script_id);
```

## Console API

```zig
// Enable console API in evaluation
var result = try runtime.evaluate(allocator,
    \\console.log('Debug message');
    \\$('div') // Like browser console
, .{
    .include_command_line_api = true,
});
```

## Complex Script

```zig
const script =
    \\(function() {
    \\  const items = document.querySelectorAll('.product');
    \\  return Array.from(items).map(item => ({
    \\    name: item.querySelector('.name')?.innerText,
    \\    price: parseFloat(item.querySelector('.price')?.innerText.replace('$', '')),
    \\    available: !item.classList.contains('out-of-stock')
    \\  })).filter(p => p.available && p.price < 100);
    \\})()
;

var result = try runtime.evaluate(allocator, script, .{
    .return_by_value = true,
});
defer result.deinit(allocator);
```
