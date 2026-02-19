# Fetch Domain

The `Fetch` domain provides methods for intercepting and modifying network requests.

## Import

```zig
const cdp = @import("cdp");
const Fetch = cdp.Fetch;
```

## Initialization

```zig
var session = try browser.newPage();
var fetch = Fetch.init(session);
try fetch.enable(.{});
```

## Methods

### enable

Enable request interception.

```zig
pub fn enable(self: *Fetch, params: EnableParams) !void
```

**Parameters:**

| Field | Type | Description |
|-------|------|-------------|
| `patterns` | `?[]RequestPattern` | URL patterns to intercept |
| `handle_auth_requests` | `?bool` | Handle auth challenges |

**Example:**

```zig
try fetch.enable(.{
    .patterns = &[_]RequestPattern{
        .{ .url_pattern = "*" },
        .{ .url_pattern = "*.js", .request_stage = .response },
    },
});
```

### disable

Disable request interception.

```zig
pub fn disable(self: *Fetch) !void
```

### continueRequest

Continue a paused request.

```zig
pub fn continueRequest(
    self: *Fetch,
    request_id: []const u8,
    params: ContinueRequestParams,
) !void
```

**Parameters:**

| Field | Type | Description |
|-------|------|-------------|
| `url` | `?[]const u8` | Override URL |
| `method` | `?[]const u8` | Override method |
| `post_data` | `?[]const u8` | Override body |
| `headers` | `?[]Header` | Override headers |

### fulfillRequest

Fulfill a request with custom response.

```zig
pub fn fulfillRequest(
    self: *Fetch,
    request_id: []const u8,
    response_code: i32,
    params: FulfillRequestParams,
) !void
```

**Parameters:**

| Field | Type | Description |
|-------|------|-------------|
| `response_headers` | `?[]Header` | Response headers |
| `body` | `?[]const u8` | Response body (base64) |
| `response_phrase` | `?[]const u8` | Status text |

### failRequest

Fail a request with an error.

```zig
pub fn failRequest(self: *Fetch, request_id: []const u8, reason: ErrorReason) !void
```

**Error Reasons:**

```zig
pub const ErrorReason = enum {
    Failed,
    Aborted,
    TimedOut,
    AccessDenied,
    ConnectionClosed,
    ConnectionReset,
    ConnectionRefused,
    ConnectionAborted,
    ConnectionFailed,
    NameNotResolved,
    InternetDisconnected,
    AddressUnreachable,
    BlockedByClient,
    BlockedByResponse,
};
```

### getResponseBody

Get the response body of a paused request.

```zig
pub fn getResponseBody(
    self: *Fetch,
    allocator: Allocator,
    request_id: []const u8,
) !ResponseBody
```

### continueWithAuth

Continue with authentication credentials.

```zig
pub fn continueWithAuth(
    self: *Fetch,
    request_id: []const u8,
    response: AuthChallengeResponse,
) !void
```

## Types

### RequestPattern

```zig
pub const RequestPattern = struct {
    url_pattern: ?[]const u8 = null,
    resource_type: ?ResourceType = null,
    request_stage: ?RequestStage = null,
};
```

### RequestStage

```zig
pub const RequestStage = enum {
    request,   // Intercept before sending
    response,  // Intercept after receiving
};
```

### Header

```zig
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};
```

## Use Cases

### Block Requests

```zig
// In event handler for Fetch.requestPaused
try fetch.failRequest(request_id, .BlockedByClient);
```

### Modify Headers

```zig
try fetch.continueRequest(request_id, .{
    .headers = &[_]Header{
        .{ .name = "X-Custom-Header", .value = "custom-value" },
    },
});
```

### Mock Response

```zig
const body = try cdp.base64.encodeAlloc(allocator, "{\"mocked\": true}");
defer allocator.free(body);

try fetch.fulfillRequest(request_id, 200, .{
    .response_headers = &[_]Header{
        .{ .name = "Content-Type", .value = "application/json" },
    },
    .body = body,
});
```

### Redirect Request

```zig
try fetch.continueRequest(request_id, .{
    .url = "https://other-url.com/endpoint",
});
```

## Events

| Event | Description |
|-------|-------------|
| `requestPaused` | Request was intercepted |
| `authRequired` | Authentication required |

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
    var fetch = cdp.Fetch.init(session);
    
    try page.enable();
    
    // Enable interception for all requests
    try fetch.enable(.{
        .patterns = &[_]cdp.Fetch.RequestPattern{
            .{ .url_pattern = "*" },
        },
    });

    // Note: To actually handle intercepted requests,
    // you'd need to listen for Fetch.requestPaused events
    // and call continueRequest/fulfillRequest/failRequest

    _ = try page.navigate(allocator, "https://example.com");

    try fetch.disable();
}
```

::: warning
Request interception requires event handling to process paused requests. Without handling `requestPaused` events, requests will hang indefinitely.
:::
