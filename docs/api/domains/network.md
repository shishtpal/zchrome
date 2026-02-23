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
try network.enable();
```

## Methods

### enable

Enable network tracking.

```zig
pub fn enable(self: *Network) !void
```

### enableWithOptions

Enable network tracking with buffer size options.

```zig
pub fn enableWithOptions(self: *Network, opts: EnableOptions) !void
```

**Options:**

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

Get the body of a response by request ID.

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

### getRequestPostData

Get POST data of a request.

```zig
pub fn getRequestPostData(
    self: *Network,
    allocator: Allocator,
    request_id: []const u8,
) ![]const u8
```

### setCacheDisabled

Enable or disable caching.

```zig
pub fn setCacheDisabled(self: *Network, disabled: bool) !void
```

### setExtraHTTPHeaders

Set extra HTTP headers for all requests.

```zig
pub fn setExtraHTTPHeaders(self: *Network, headers: std.json.Value) !void
```

### emulateNetworkConditions

Emulate network conditions (offline, latency, throughput).

```zig
pub fn emulateNetworkConditions(self: *Network, opts: NetworkConditions) !void
```

**Options:**

```zig
pub const NetworkConditions = struct {
    offline: bool = false,
    latency: f64 = 0,
    download_throughput: f64 = -1,  // -1 = no limit
    upload_throughput: f64 = -1,
    connection_type: ?[]const u8 = null,  // "cellular3g", "wifi", etc.
};
```

### setBlockedURLs

Block requests to specific URLs.

```zig
pub fn setBlockedURLs(self: *Network, urls: []const []const u8) !void
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

### setRequestInterception

Set request interception patterns (deprecated, use Fetch domain instead).

```zig
pub fn setRequestInterception(self: *Network, patterns: []const RequestPattern) !void
```

### continueInterceptedRequest

Continue an intercepted request with optional modifications.

```zig
pub fn continueInterceptedRequest(
    self: *Network,
    interception_id: []const u8,
    opts: ContinueInterceptedRequestOptions,
) !void
```

### searchInResponseBody

Search for content in a response body.

```zig
pub fn searchInResponseBody(
    self: *Network,
    allocator: Allocator,
    request_id: []const u8,
    query: []const u8,
    case_sensitive: bool,
    is_regex: bool,
) ![]SearchMatch
```

### replayXHR

Replay an XHR request.

```zig
pub fn replayXHR(self: *Network, request_id: []const u8) !void
```

### loadNetworkResource

Load a network resource (for service workers).

```zig
pub fn loadNetworkResource(
    self: *Network,
    allocator: Allocator,
    frame_id: ?[]const u8,
    url: []const u8,
    opts: LoadNetworkResourceOptions,
) !LoadedResource
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
| `RequestIntercepted` | Request intercepted (when interception enabled) |
| `WebSocketCreated` | WebSocket connection opened |
| `WebSocketClosed` | WebSocket connection closed |
| `WebSocketFrameReceived` | WebSocket frame received |
| `WebSocketFrameSent` | WebSocket frame sent |
| `EventSourceMessageReceived` | Server-sent event received |

## Types

### Request

```zig
pub const Request = struct {
    url: []const u8,
    method: []const u8,
    headers: std.json.Value,
    post_data: ?[]const u8 = null,
    has_post_data: ?bool = null,
    mixed_content_type: ?[]const u8 = null,
    initial_priority: ?[]const u8 = null,
    referrer_policy: ?[]const u8 = null,
    is_link_preload: ?bool = null,
};
```

### Response

```zig
pub const Response = struct {
    url: []const u8,
    status: i64,
    status_text: []const u8,
    headers: std.json.Value,
    mime_type: []const u8,
    charset: ?[]const u8 = null,
    request_headers: ?std.json.Value = null,
    connection_reused: ?bool = null,
    remote_ip_address: ?[]const u8 = null,
    remote_port: ?i64 = null,
    from_disk_cache: ?bool = null,
    from_service_worker: ?bool = null,
    protocol: ?[]const u8 = null,
    security_state: ?[]const u8 = null,
};
```

### ResourceType

```zig
pub const ResourceType = enum {
    Document,
    Stylesheet,
    Image,
    Media,
    Font,
    Script,
    TextTrack,
    XHR,
    Fetch,
    Prefetch,
    EventSource,
    WebSocket,
    Manifest,
    SignedExchange,
    Ping,
    CSPViolationReport,
    Preflight,
    Other,
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
    try network.enable();

    // Disable cache
    try network.setCacheDisabled(true);

    // Block tracking URLs
    try network.setBlockedURLs(&.{
        "*://analytics.*",
        "*://tracking.*",
    });

    // Emulate slow 3G connection
    try network.emulateNetworkConditions(.{
        .offline = false,
        .latency = 400,
        .download_throughput = 500 * 1024,  // 500 KB/s
        .upload_throughput = 500 * 1024,
        .connection_type = "cellular3g",
    });

    _ = try page.navigate(allocator, "https://example.com");

    // Note: To capture request/response data, you'd need to
    // listen to network events via the session's event system
}
```

## User Agent Override

To override the user agent, use the **Emulation** domain:

```zig
var emulation = cdp.Emulation.init(session);
try emulation.setUserAgentOverride("MyBot/1.0", null);
```

Or via CLI:

```bash
zchrome set ua "MyBot/1.0"
```
