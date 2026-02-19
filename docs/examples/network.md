# Network Interception

Monitor and modify network traffic.

## Enable Network Tracking

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
    var network = cdp.Network.init(session);
    
    try page.enable();
    try network.enable(.{});

    _ = try page.navigate(allocator, "https://example.com");

    // Network events would be captured here
    // (Event handling requires additional implementation)
}
```

## Configure Network

### Disable Cache

```zig
try network.setCacheDisabled(true);
```

### Custom User Agent

```zig
try network.setUserAgentOverride("CustomBot/1.0");
```

### Extra Headers

```zig
var headers = std.StringHashMap([]const u8).init(allocator);
defer headers.deinit();

try headers.put("Authorization", "Bearer token123");
try headers.put("X-Custom-Header", "value");

try network.setExtraHTTPHeaders(headers);
```

## Network Conditions

### Offline Mode

```zig
try network.emulateNetworkConditions(
    true,  // offline
    0,     // latency
    0,     // download throughput
    0,     // upload throughput
);
```

### Slow 3G

```zig
try network.emulateNetworkConditions(
    false,   // offline
    400,     // latency (ms)
    400000,  // download throughput (bytes/sec) ~400KB/s
    400000,  // upload throughput
);
```

### Fast 3G

```zig
try network.emulateNetworkConditions(
    false,
    100,
    1500000,  // ~1.5MB/s
    750000,
);
```

### Regular 4G

```zig
try network.emulateNetworkConditions(
    false,
    20,
    4000000,  // ~4MB/s
    3000000,
);
```

## Clear Data

```zig
// Clear browser cache
try network.clearBrowserCache();

// Clear cookies
try network.clearBrowserCookies();
```

## Request Interception

For modifying requests in-flight, use the Fetch domain:

```zig
var fetch = cdp.Fetch.init(session);

// Enable interception
try fetch.enable(.{
    .patterns = &[_]cdp.Fetch.RequestPattern{
        .{ .url_pattern = "*" },  // All requests
    },
});

// Note: You need to handle Fetch.requestPaused events
// and call continueRequest/fulfillRequest/failRequest
```

### Block Requests

```zig
// In requestPaused handler:
try fetch.failRequest(request_id, .BlockedByClient);
```

### Modify Request URL

```zig
try fetch.continueRequest(request_id, .{
    .url = "https://different-url.com/endpoint",
});
```

### Mock Response

```zig
const body = try cdp.base64.encodeAlloc(allocator, "{\"mocked\": true}");
defer allocator.free(body);

try fetch.fulfillRequest(request_id, 200, .{
    .response_headers = &[_]cdp.Fetch.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    },
    .body = body,
});
```

## Block Resource Types

```zig
// Block images
try fetch.enable(.{
    .patterns = &[_]cdp.Fetch.RequestPattern{
        .{ .resource_type = .image },
    },
});

// In handler: fail all image requests
try fetch.failRequest(request_id, .BlockedByClient);
```

## Block Specific Domains

```zig
// Block analytics/ads
const blocked_domains = [_][]const u8{
    "*google-analytics.com*",
    "*facebook.com/tr*",
    "*doubleclick.net*",
};

try fetch.enable(.{
    .patterns = blk: {
        var patterns: [blocked_domains.len]cdp.Fetch.RequestPattern = undefined;
        for (blocked_domains, 0..) |domain, i| {
            patterns[i] = .{ .url_pattern = domain };
        }
        break :blk &patterns;
    },
});

// Block all matching requests in handler
```

## Response Interception

Intercept and modify responses:

```zig
try fetch.enable(.{
    .patterns = &[_]cdp.Fetch.RequestPattern{
        .{ .url_pattern = "*/api/*", .request_stage = .response },
    },
});

// In requestPaused handler (response stage):
// 1. Get original response
const body = try fetch.getResponseBody(allocator, request_id);
defer body.deinit(allocator);

// 2. Modify body
const modified = try modifyJson(body.body);

// 3. Return modified response
try fetch.fulfillRequest(request_id, 200, .{
    .body = try cdp.base64.encodeAlloc(allocator, modified),
});
```

## Capture HAR-like Data

```zig
// This would require event handling
// Conceptual example:

const RequestLog = struct {
    url: []const u8,
    method: []const u8,
    status: i64,
    size: usize,
    duration_ms: f64,
};

var requests = std.ArrayList(RequestLog).init(allocator);
defer requests.deinit();

// On requestWillBeSent: record start time, url, method
// On responseReceived: record status, headers
// On loadingFinished: record final size, calculate duration
```

## Wait for Network Idle

```zig
// Via JavaScript
var runtime = cdp.Runtime.init(session);

_ = try runtime.evaluate(allocator,
    \\new Promise(resolve => {
    \\  let timeout;
    \\  const observer = new PerformanceObserver(() => {
    \\    clearTimeout(timeout);
    \\    timeout = setTimeout(resolve, 500);
    \\  });
    \\  observer.observe({ entryTypes: ['resource'] });
    \\  timeout = setTimeout(resolve, 500);
    \\})
, .{ .await_promise = true });
```

## Performance Tips

1. **Disable unnecessary resources** for faster scraping:
   ```zig
   // Block images, fonts, stylesheets
   try fetch.enable(.{
       .patterns = &[_]cdp.Fetch.RequestPattern{
           .{ .resource_type = .image },
           .{ .resource_type = .font },
           .{ .resource_type = .stylesheet },
       },
   });
   ```

2. **Disable cache** for fresh data:
   ```zig
   try network.setCacheDisabled(true);
   ```

3. **Set appropriate timeouts** for slow networks.
