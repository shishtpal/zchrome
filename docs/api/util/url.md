# URL Utilities

Functions for parsing and manipulating URLs.

## Import

```zig
const cdp = @import("cdp");
const url = cdp.url;
```

## Functions

### parse

Parse a URL into its components.

```zig
pub fn parse(input: []const u8) !Url
```

**Returns:**

```zig
pub const Url = struct {
    scheme: []const u8,    // "https"
    host: []const u8,      // "example.com"
    port: ?u16,            // 443 or null
    path: []const u8,      // "/path/to/page"
    query: ?[]const u8,    // "key=value" or null
    fragment: ?[]const u8, // "section" or null
};
```

**Example:**

```zig
const parsed = try url.parse("https://example.com:8080/path?query=1#section");

std.debug.print("Scheme: {s}\n", .{parsed.scheme});   // https
std.debug.print("Host: {s}\n", .{parsed.host});       // example.com
std.debug.print("Port: {?}\n", .{parsed.port});       // 8080
std.debug.print("Path: {s}\n", .{parsed.path});       // /path
std.debug.print("Query: {?s}\n", .{parsed.query});    // query=1
std.debug.print("Fragment: {?s}\n", .{parsed.fragment}); // section
```

### encode

URL-encode a string.

```zig
pub fn encode(allocator: Allocator, input: []const u8) ![]u8
```

**Example:**

```zig
const encoded = try url.encode(allocator, "hello world!");
defer allocator.free(encoded);
// Result: "hello%20world%21"
```

### decode

URL-decode a string.

```zig
pub fn decode(allocator: Allocator, input: []const u8) ![]u8
```

**Example:**

```zig
const decoded = try url.decode(allocator, "hello%20world%21");
defer allocator.free(decoded);
// Result: "hello world!"
```

## Common Use Cases

### Parse WebSocket URL

```zig
const ws_url = "ws://127.0.0.1:9222/devtools/browser/abc123";
const parsed = try url.parse(ws_url);

std.debug.print("Host: {s}:{?}\n", .{parsed.host, parsed.port});
// Host: 127.0.0.1:9222
```

### Build URL with Query

```zig
const base = "https://example.com/search";
const query = try url.encode(allocator, "hello world");
defer allocator.free(query);

const full_url = try std.fmt.allocPrint(allocator, "{s}?q={s}", .{base, query});
defer allocator.free(full_url);
// Result: https://example.com/search?q=hello%20world
```

### Extract Domain

```zig
const page_url = "https://sub.example.com/page";
const parsed = try url.parse(page_url);

std.debug.print("Domain: {s}\n", .{parsed.host});
// Domain: sub.example.com
```

## Error Handling

```zig
const parsed = url.parse("not a valid url") catch |err| {
    std.debug.print("Invalid URL: {}\n", .{err});
    return;
};
```
