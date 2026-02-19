# Sessions & Targets

Understanding sessions and targets is key to working with multiple tabs and browser contexts.

## Concepts

### Targets

A **target** is anything that can be debugged:
- Browser tabs (pages)
- Service workers
- Shared workers
- Browser extensions
- The browser itself

### Sessions

A **session** is an active connection to a specific target. Sessions are identified by a unique `sessionId`.

```
Browser (ws://...)
├── Target 1 (page) → Session A
├── Target 2 (page) → Session B
└── Target 3 (worker) → Session C
```

## Working with Sessions

### Creating a Session

```zig
var browser = try cdp.Browser.launch(.{ ... });

// newPage() creates a target and attaches a session
var session = try browser.newPage();
defer session.detach() catch {};
```

### Using Domain Clients

Domain clients operate on a session:

```zig
// All commands go through this session
var page = cdp.Page.init(session);
var dom = cdp.DOM.init(session);
var runtime = cdp.Runtime.init(session);
```

### Multiple Sessions

Work with multiple tabs simultaneously:

```zig
var browser = try cdp.Browser.launch(.{ ... });

// Open two pages
var session1 = try browser.newPage();
var session2 = try browser.newPage();

// Each session is independent
var page1 = cdp.Page.init(session1);
var page2 = cdp.Page.init(session2);

_ = try page1.navigate(allocator, "https://example.com");
_ = try page2.navigate(allocator, "https://google.com");

// Clean up
session1.detach() catch {};
session2.detach() catch {};
```

### Detaching Sessions

When done with a session:

```zig
try session.detach();
// Session is no longer usable
// The target (tab) remains open
```

## Target Management

### List All Targets

```zig
var target = cdp.Target.init(browser.connection);
const targets = try target.getTargets(allocator);
defer {
    for (targets) |*t| {
        t.deinit(allocator);
    }
    allocator.free(targets);
}

for (targets) |t| {
    std.debug.print("Type: {s}, Title: {s}\n", .{t.type, t.title});
}
```

### Target Types

| Type | Description |
|------|-------------|
| `"page"` | Browser tab |
| `"background_page"` | Extension background page |
| `"service_worker"` | Service worker |
| `"shared_worker"` | Shared worker |
| `"browser"` | Browser process |
| `"webview"` | WebView |

### Close Target

```zig
try browser.closePage(target_id);
```

### Get Pages Only

```zig
const pages = try browser.pages();
// Returns only targets with type "page"
```

## Session Lifecycle

```
1. Browser.newPage()
   └── Creates new target (about:blank)
   └── Attaches session
   └── Returns Session*

2. Use session for CDP commands
   └── page.navigate()
   └── dom.querySelector()
   └── runtime.evaluate()

3. session.detach()
   └── Detaches from target
   └── Target remains (tab stays open)

4. browser.closePage(target_id)
   └── Closes the target
```

## TargetInfo Structure

```zig
pub const TargetInfo = struct {
    target_id: []const u8,        // Unique target ID
    type: []const u8,             // "page", "worker", etc.
    title: []const u8,            // Page title
    url: []const u8,              // Current URL
    attached: bool,               // Has active session?
    opener_id: ?[]const u8,       // Parent target (if popup)
    browser_context_id: ?[]const u8,
};
```

## Example: Multi-Tab Workflow

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

    // Open multiple tabs
    const urls = [_][]const u8{
        "https://example.com",
        "https://httpbin.org/get",
        "https://jsonplaceholder.typicode.com/todos/1",
    };

    var sessions: [urls.len]*cdp.Session = undefined;
    
    for (urls, 0..) |url, i| {
        sessions[i] = try browser.newPage();
        var page = cdp.Page.init(sessions[i]);
        try page.enable();
        _ = try page.navigate(allocator, url);
    }

    // Process each tab
    for (sessions, 0..) |session, i| {
        var runtime = cdp.Runtime.init(session);
        try runtime.enable();
        
        const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";
        std.debug.print("Tab {}: {s}\n", .{i, title});
    }

    // Clean up sessions
    for (sessions) |session| {
        session.detach() catch {};
    }
}
```
