# Storage Domain

The `Storage` domain provides methods for managing cookies and local storage.

## Import

```zig
const cdp = @import("cdp");
const Storage = cdp.Storage;
```

## Initialization

```zig
var session = try browser.newPage();
var storage = Storage.init(session);
```

## Methods

### getCookies

Get all cookies.

```zig
pub fn getCookies(
    self: *Storage,
    allocator: Allocator,
    urls: ?[]const []const u8,
) ![]Cookie
```

**Parameters:**
- `urls` - Optional list of URLs to filter cookies

**Returns:** Slice of `Cookie` (caller must deinit each and free slice)

**Example:**

```zig
const cookies = try storage.getCookies(allocator, null);
defer {
    for (cookies) |*c| c.deinit(allocator);
    allocator.free(cookies);
}

for (cookies) |cookie| {
    std.debug.print("{s}={s}\n", .{cookie.name, cookie.value});
}
```

### setCookie

Set a cookie.

```zig
pub fn setCookie(self: *Storage, params: SetCookieParams) !void
```

**Parameters:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `[]const u8` | Cookie name |
| `value` | `[]const u8` | Cookie value |
| `url` | `?[]const u8` | URL to associate |
| `domain` | `?[]const u8` | Cookie domain |
| `path` | `?[]const u8` | Cookie path |
| `secure` | `?bool` | HTTPS only |
| `http_only` | `?bool` | HTTP only (no JS) |
| `same_site` | `?SameSite` | SameSite policy |
| `expires` | `?f64` | Expiration timestamp |

**Example:**

```zig
try storage.setCookie(.{
    .name = "session",
    .value = "abc123",
    .domain = ".example.com",
    .path = "/",
    .secure = true,
    .http_only = true,
    .same_site = .strict,
});
```

### deleteCookies

Delete cookies.

```zig
pub fn deleteCookies(
    self: *Storage,
    name: []const u8,
    url: ?[]const u8,
    domain: ?[]const u8,
    path: ?[]const u8,
) !void
```

**Example:**

```zig
// Delete specific cookie
try storage.deleteCookies("session", null, ".example.com", "/");

// Delete all cookies for a URL
try storage.deleteCookies("*", "https://example.com", null, null);
```

### clearCookies

Clear all cookies.

```zig
pub fn clearCookies(self: *Storage) !void
```

### getStorageKeyForFrame

Get storage key for a frame.

```zig
pub fn getStorageKeyForFrame(
    self: *Storage,
    allocator: Allocator,
    frame_id: []const u8,
) ![]const u8
```

### clearDataForOrigin

Clear storage data for an origin.

```zig
pub fn clearDataForOrigin(
    self: *Storage,
    origin: []const u8,
    storage_types: []const u8,
) !void
```

**Storage types:** `"cookies"`, `"local_storage"`, `"indexeddb"`, `"websql"`, `"appcache"`, `"all"`

**Example:**

```zig
try storage.clearDataForOrigin("https://example.com", "all");
```

## Types

### Cookie

```zig
pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    domain: []const u8,
    path: []const u8,
    expires: f64,
    size: i64,
    http_only: bool,
    secure: bool,
    session: bool,
    same_site: ?SameSite = null,

    pub fn deinit(self: *Cookie, allocator: Allocator) void;
};
```

### SameSite

```zig
pub const SameSite = enum {
    strict,
    lax,
    none,
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
    var storage = cdp.Storage.init(session);
    
    try page.enable();

    _ = try page.navigate(allocator, "https://example.com");

    // Wait for load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Get all cookies
    const cookies = try storage.getCookies(allocator, null);
    defer {
        for (cookies) |*c| c.deinit(allocator);
        allocator.free(cookies);
    }

    std.debug.print("Cookies ({}):\n", .{cookies.len});
    for (cookies) |cookie| {
        std.debug.print("  {s}={s} ({s})\n", .{
            cookie.name, cookie.value, cookie.domain,
        });
    }

    // Set a new cookie
    try storage.setCookie(.{
        .name = "my_cookie",
        .value = "test_value",
        .domain = ".example.com",
        .path = "/",
    });

    // Clear all cookies
    // try storage.clearCookies();
}
```
