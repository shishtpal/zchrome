# Network Domain

The `Network` domain provides methods for tracking and intercepting network requests.

## Import

```zig
const cdp = @import("cdp");
const Network = cdp.Network;
```

## Initialization

```zig
var session = try browser.newPage();
var network = Network.init(session);
try network.enable(.{});
```

## Methods

### enable

Enable network tracking.

```zig
pub fn enable(self: *Network, params: EnableParams) !void
```

**Parameters:**

| Field | Type | Description |
|-------|------|-------------|
| `max_total_buffer_size` | `?i64` | Buffer size for resource bodies |
| `max_resource_buffer_size` | `?i64` | Per-resource buffer size |
| `max_post_data_size` | `?i64` | Max POST data to capture |

### disable

Disable network tracking.

```zig
pub fn disable(self: *Network) !void
```

### getResponseBody

Get the body of a response.

```zig
pub fn getResponseBody(
    self: *Network,
    allocator: Allocator,
    request_id: []const u8,
) !ResponseBody
```

**Returns:**

```zig
pub const ResponseBody = struct {
    body: []const u8,
    base64_encoded: bool,

    pub fn deinit(self: *ResponseBody, allocator: Allocator) void;
};
```

### setCacheDisabled

Enable or disable caching.

```zig
pub fn setCacheDisabled(self: *Network, disabled: bool) !void
```

### setUserAgentOverride

Override the user agent.

```zig
pub fn setUserAgentOverride(self: *Network, user_agent: []const u8) !void
```

### setExtraHTTPHeaders

Set extra HTTP headers for all requests.

```zig
pub fn setExtraHTTPHeaders(self: *Network, headers: std.StringHashMap([]const u8)) !void
```

### emulateNetworkConditions

Emulate network conditions.

```zig
pub fn emulateNetworkConditions(
    self: *Network,
    offline: bool,
    latency: f64,
    download_throughput: f64,
    upload_throughput: f64,
) !void
```

### clearBrowserCache

Clear browser cache.

```zig
pub fn clearBrowserCache(self: *Network) !void
```

### clearBrowserCookies

Clear browser cookies.

```zig
pub fn clearBrowserCookies(self: *Network) !void
```

## Events

Network events are fired as requests are made:

| Event | Description |
|-------|-------------|
| `RequestWillBeSent` | Request is about to be sent |
| `ResponseReceived` | Response headers received |
| `LoadingFinished` | Request completed |
| `LoadingFailed` | Request failed |
| `DataReceived` | Data chunk received |

## Types

### Request

```zig
pub const Request = struct {
    url: []const u8,
    method: []const u8,
    headers: std.StringHashMap([]const u8),
    post_data: ?[]const u8 = null,
};
```

### Response

```zig
pub const Response = struct {
    url: []const u8,
    status: i64,
    status_text: []const u8,
    headers: std.StringHashMap([]const u8),
    mime_type: []const u8,
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
    var network = cdp.Network.init(session);
    
    try page.enable();
    try network.enable(.{});

    // Disable cache
    try network.setCacheDisabled(true);

    // Set custom user agent
    try network.setUserAgentOverride("MyBot/1.0");

    _ = try page.navigate(allocator, "https://httpbin.org/get");

    // Note: To capture request/response data, you'd need to
    // listen to network events
}
```
