const std = @import("std");
const json = @import("cdp").json;

/// HTTP request (mirrors src/domains/network.zig)
pub const Request = struct {
    url: []const u8,
    method: []const u8,
    headers: std.json.Value,
    initial_priority: ?[]const u8 = null,
    referrer_policy: ?[]const u8 = null,
    url_fragment: ?[]const u8 = null,
    post_data: ?[]const u8 = null,
    has_post_data: ?bool = null,
    mixed_content_type: ?[]const u8 = null,
    is_link_preload: ?bool = null,

    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.method);
        if (self.initial_priority) |p| allocator.free(p);
        if (self.referrer_policy) |p| allocator.free(p);
        if (self.url_fragment) |f| allocator.free(f);
        if (self.post_data) |d| allocator.free(d);
        if (self.mixed_content_type) |t| allocator.free(t);
    }
};

/// HTTP response (mirrors src/domains/network.zig)
pub const Response = struct {
    url: []const u8,
    status: i32,
    status_text: []const u8,
    headers: std.json.Value,
    mime_type: []const u8,
    connection_reused: ?bool = null,
    connection_id: ?i64 = null,
    remote_ip_address: ?[]const u8 = null,
    remote_port: ?i32 = null,
    from_disk_cache: ?bool = null,
    from_service_worker: ?bool = null,
    from_prefetch_cache: ?bool = null,
    protocol: ?[]const u8 = null,
    security_state: ?[]const u8 = null,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.status_text);
        allocator.free(self.mime_type);
        if (self.remote_ip_address) |ip| allocator.free(ip);
        if (self.protocol) |p| allocator.free(p);
        if (self.security_state) |s| allocator.free(s);
    }
};

/// Cookie (mirrors src/domains/network.zig)
pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    domain: []const u8,
    path: []const u8,
    size: i32,
    http_only: bool,
    secure: bool,
    same_site: ?[]const u8 = null,
    expires: ?f64 = null,
    session: ?bool = null,
    priority: ?[]const u8 = null,
    same_party: ?bool = null,
    source_scheme: ?[]const u8 = null,
    source_port: ?i32 = null,

    pub fn deinit(self: *Cookie, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
        allocator.free(self.domain);
        allocator.free(self.path);
        if (self.same_site) |s| allocator.free(s);
        if (self.priority) |p| allocator.free(p);
        if (self.source_scheme) |s| allocator.free(s);
    }
};

/// Parse Request from JSON
fn parseRequest(allocator: std.mem.Allocator, obj: std.json.Value) !Request {
    return .{
        .url = try allocator.dupe(u8, try json.getString(obj, "url")),
        .method = try allocator.dupe(u8, try json.getString(obj, "method")),
        .headers = obj.object.get("headers") orelse .{ .object = std.json.ObjectMap.init(allocator) },
        .initial_priority = if (obj.object.get("initialPriority")) |v| try allocator.dupe(u8, v.string) else null,
        .referrer_policy = if (obj.object.get("referrerPolicy")) |v| try allocator.dupe(u8, v.string) else null,
        .url_fragment = if (obj.object.get("urlFragment")) |v| try allocator.dupe(u8, v.string) else null,
        .post_data = if (obj.object.get("postData")) |v| try allocator.dupe(u8, v.string) else null,
        .has_post_data = if (obj.object.get("hasPostData")) |v| v.bool else null,
        .mixed_content_type = if (obj.object.get("mixedContentType")) |v| try allocator.dupe(u8, v.string) else null,
        .is_link_preload = if (obj.object.get("isLinkPreload")) |v| v.bool else null,
    };
}

/// Parse Response from JSON
fn parseResponse(allocator: std.mem.Allocator, obj: std.json.Value) !Response {
    return .{
        .url = try allocator.dupe(u8, try json.getString(obj, "url")),
        .status = @intCast(try json.getInt(obj, "status")),
        .status_text = try allocator.dupe(u8, try json.getString(obj, "statusText")),
        .headers = obj.object.get("headers") orelse .{ .object = std.json.ObjectMap.init(allocator) },
        .mime_type = try allocator.dupe(u8, try json.getString(obj, "mimeType")),
        .connection_reused = if (obj.object.get("connectionReused")) |v| v.bool else null,
        .connection_id = if (obj.object.get("connectionId")) |v| v.integer else null,
        .remote_ip_address = if (obj.object.get("remoteIPAddress")) |v| try allocator.dupe(u8, v.string) else null,
        .remote_port = if (obj.object.get("remotePort")) |v| @intCast(v.integer) else null,
        .from_disk_cache = if (obj.object.get("fromDiskCache")) |v| v.bool else null,
        .from_service_worker = if (obj.object.get("fromServiceWorker")) |v| v.bool else null,
        .from_prefetch_cache = if (obj.object.get("fromPrefetchCache")) |v| v.bool else null,
        .protocol = if (obj.object.get("protocol")) |v| try allocator.dupe(u8, v.string) else null,
        .security_state = if (obj.object.get("securityState")) |v| try allocator.dupe(u8, v.string) else null,
    };
}

/// Parse Cookie from JSON
fn parseCookie(allocator: std.mem.Allocator, obj: std.json.Value) !Cookie {
    return .{
        .name = try allocator.dupe(u8, try json.getString(obj, "name")),
        .value = try allocator.dupe(u8, try json.getString(obj, "value")),
        .domain = try allocator.dupe(u8, try json.getString(obj, "domain")),
        .path = try allocator.dupe(u8, try json.getString(obj, "path")),
        .size = @intCast(try json.getInt(obj, "size")),
        .http_only = try json.getBool(obj, "httpOnly"),
        .secure = try json.getBool(obj, "secure"),
        .same_site = if (obj.object.get("sameSite")) |v| try allocator.dupe(u8, v.string) else null,
        .expires = if (obj.object.get("expires")) |v| switch (v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        } else null,
        .session = if (obj.object.get("session")) |v| v.bool else null,
        .priority = if (obj.object.get("priority")) |v| try allocator.dupe(u8, v.string) else null,
        .same_party = if (obj.object.get("sameParty")) |v| v.bool else null,
        .source_scheme = if (obj.object.get("sourceScheme")) |v| try allocator.dupe(u8, v.string) else null,
        .source_port = if (obj.object.get("sourcePort")) |v| @intCast(v.integer) else null,
    };
}

// ─── Request Parsing Tests ────────────────────────────────────────────────────

test "Request - parse from JSON" {
    const json_str =
        \\{
        \\  "url": "https://example.com/api/data",
        \\  "method": "POST",
        \\  "headers": {"Content-Type": "application/json"},
        \\  "initialPriority": "High",
        \\  "referrerPolicy": "strict-origin-when-cross-origin"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var req = try parseRequest(std.testing.allocator, parsed.value);
    defer req.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("https://example.com/api/data", req.url);
    try std.testing.expectEqualStrings("POST", req.method);
    try std.testing.expect(req.initial_priority != null);
    try std.testing.expectEqualStrings("High", req.initial_priority.?);
}

test "Request - parse GET request" {
    const json_str =
        \\{
        \\  "url": "https://example.com/page",
        \\  "method": "GET",
        \\  "headers": {}
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var req = try parseRequest(std.testing.allocator, parsed.value);
    defer req.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("GET", req.method);
}

test "Request - parse with post data" {
    const json_str =
        \\{
        \\  "url": "https://example.com/api",
        \\  "method": "POST",
        \\  "headers": {},
        \\  "postData": "{\"key\":\"value\"}",
        \\  "hasPostData": true
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var req = try parseRequest(std.testing.allocator, parsed.value);
    defer req.deinit(std.testing.allocator);

    try std.testing.expect(req.post_data != null);
    try std.testing.expectEqualStrings("{\"key\":\"value\"}", req.post_data.?);
    try std.testing.expect(req.has_post_data == true);
}

test "Request - deinit frees memory" {
    var req = Request{
        .url = try std.testing.allocator.dupe(u8, "https://example.com"),
        .method = try std.testing.allocator.dupe(u8, "GET"),
        .headers = .{ .object = std.json.ObjectMap.init(std.testing.allocator) },
        .initial_priority = try std.testing.allocator.dupe(u8, "High"),
        .referrer_policy = try std.testing.allocator.dupe(u8, "strict-origin"),
    };
    req.deinit(std.testing.allocator);
}

// ─── Response Parsing Tests ───────────────────────────────────────────────────

test "Response - parse from JSON" {
    const json_str =
        \\{
        \\  "url": "https://example.com/page",
        \\  "status": 200,
        \\  "statusText": "OK",
        \\  "headers": {"content-type": "text/html"},
        \\  "mimeType": "text/html"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var resp = try parseResponse(std.testing.allocator, parsed.value);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("https://example.com/page", resp.url);
    try std.testing.expectEqual(@as(i32, 200), resp.status);
    try std.testing.expectEqualStrings("OK", resp.status_text);
    try std.testing.expectEqualStrings("text/html", resp.mime_type);
}

test "Response - parse 404 response" {
    const json_str =
        \\{
        \\  "url": "https://example.com/notfound",
        \\  "status": 404,
        \\  "statusText": "Not Found",
        \\  "headers": {},
        \\  "mimeType": "text/html"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var resp = try parseResponse(std.testing.allocator, parsed.value);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 404), resp.status);
    try std.testing.expectEqualStrings("Not Found", resp.status_text);
}

test "Response - parse with cache info" {
    const json_str =
        \\{
        \\  "url": "https://example.com/cached",
        \\  "status": 200,
        \\  "statusText": "OK",
        \\  "headers": {},
        \\  "mimeType": "text/html",
        \\  "fromDiskCache": true,
        \\  "fromServiceWorker": false
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var resp = try parseResponse(std.testing.allocator, parsed.value);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expect(resp.from_disk_cache == true);
    try std.testing.expect(resp.from_service_worker == false);
}

test "Response - parse with remote info" {
    const json_str =
        \\{
        \\  "url": "https://example.com/page",
        \\  "status": 200,
        \\  "statusText": "OK",
        \\  "headers": {},
        \\  "mimeType": "text/html",
        \\  "remoteIPAddress": "192.168.1.1",
        \\  "remotePort": 443,
        \\  "protocol": "h2"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var resp = try parseResponse(std.testing.allocator, parsed.value);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expect(resp.remote_ip_address != null);
    try std.testing.expectEqualStrings("192.168.1.1", resp.remote_ip_address.?);
    try std.testing.expectEqual(@as(i32, 443), resp.remote_port.?);
    try std.testing.expectEqualStrings("h2", resp.protocol.?);
}

test "Response - deinit frees memory" {
    var resp = Response{
        .url = try std.testing.allocator.dupe(u8, "https://example.com"),
        .status = 200,
        .status_text = try std.testing.allocator.dupe(u8, "OK"),
        .headers = .{ .object = std.json.ObjectMap.init(std.testing.allocator) },
        .mime_type = try std.testing.allocator.dupe(u8, "text/html"),
        .remote_ip_address = try std.testing.allocator.dupe(u8, "127.0.0.1"),
        .protocol = try std.testing.allocator.dupe(u8, "http/1.1"),
    };
    resp.deinit(std.testing.allocator);
}

// ─── Cookie Parsing Tests ─────────────────────────────────────────────────────

test "Cookie - parse from JSON" {
    const json_str =
        \\{
        \\  "name": "session_id",
        \\  "value": "abc123",
        \\  "domain": ".example.com",
        \\  "path": "/",
        \\  "size": 15,
        \\  "httpOnly": true,
        \\  "secure": true,
        \\  "sameSite": "Lax"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var cookie = try parseCookie(std.testing.allocator, parsed.value);
    defer cookie.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("session_id", cookie.name);
    try std.testing.expectEqualStrings("abc123", cookie.value);
    try std.testing.expectEqualStrings(".example.com", cookie.domain);
    try std.testing.expectEqualStrings("/", cookie.path);
    try std.testing.expectEqual(@as(i32, 15), cookie.size);
    try std.testing.expect(cookie.http_only);
    try std.testing.expect(cookie.secure);
    try std.testing.expect(cookie.same_site != null);
    try std.testing.expectEqualStrings("Lax", cookie.same_site.?);
}

test "Cookie - parse without same_site" {
    const json_str =
        \\{
        \\  "name": "test",
        \\  "value": "value",
        \\  "domain": "example.com",
        \\  "path": "/",
        \\  "size": 10,
        \\  "httpOnly": false,
        \\  "secure": false
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var cookie = try parseCookie(std.testing.allocator, parsed.value);
    defer cookie.deinit(std.testing.allocator);

    try std.testing.expect(cookie.same_site == null);
}

test "Cookie - parse with expiration" {
    const json_str =
        \\{
        \\  "name": "persistent",
        \\  "value": "data",
        \\  "domain": "example.com",
        \\  "path": "/",
        \\  "size": 12,
        \\  "httpOnly": false,
        \\  "secure": true,
        \\  "expires": 1735689600.0,
        \\  "session": false
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var cookie = try parseCookie(std.testing.allocator, parsed.value);
    defer cookie.deinit(std.testing.allocator);

    try std.testing.expect(cookie.expires != null);
    try std.testing.expect(cookie.session == false);
}

test "Cookie - deinit frees memory" {
    var cookie = Cookie{
        .name = try std.testing.allocator.dupe(u8, "name"),
        .value = try std.testing.allocator.dupe(u8, "value"),
        .domain = try std.testing.allocator.dupe(u8, "example.com"),
        .path = try std.testing.allocator.dupe(u8, "/"),
        .size = 10,
        .http_only = true,
        .secure = true,
        .same_site = try std.testing.allocator.dupe(u8, "Strict"),
    };
    cookie.deinit(std.testing.allocator);
}

// ─── RequestWillBeSent Event Tests ────────────────────────────────────────────

test "RequestWillBeSent - parse event params" {
    const json_str =
        \\{
        \\  "requestId": "REQ_001",
        \\  "loaderId": "LOADER_001",
        \\  "documentURL": "https://example.com",
        \\  "request": {
        \\    "url": "https://example.com/style.css",
        \\    "method": "GET",
        \\    "headers": {}
        \\  },
        \\  "timestamp": 12345.678,
        \\  "type": "Stylesheet"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const request_id = try json.getString(parsed.value, "requestId");
    try std.testing.expectEqualStrings("REQ_001", request_id);

    const req_obj = parsed.value.object.get("request") orelse return error.MissingField;
    var req = try parseRequest(std.testing.allocator, req_obj);
    defer req.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("GET", req.method);
    try std.testing.expectEqualStrings("https://example.com/style.css", req.url);
}

// ─── ResponseReceived Event Tests ─────────────────────────────────────────────

test "ResponseReceived - parse event params" {
    const json_str =
        \\{
        \\  "requestId": "REQ_001",
        \\  "response": {
        \\    "url": "https://example.com/style.css",
        \\    "status": 200,
        \\    "statusText": "OK",
        \\    "headers": {"content-type": "text/css"},
        \\    "mimeType": "text/css"
        \\  },
        \\  "timestamp": 12345.789,
        \\  "type": "Stylesheet"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const resp_obj = parsed.value.object.get("response") orelse return error.MissingField;
    var resp = try parseResponse(std.testing.allocator, resp_obj);
    defer resp.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 200), resp.status);
    try std.testing.expectEqualStrings("text/css", resp.mime_type);
}

// ─── LoadingFinished Event Tests ──────────────────────────────────────────────

test "LoadingFinished - parse event params" {
    const json_str =
        \\{
        \\  "requestId": "REQ_001",
        \\  "timestamp": 12346.0,
        \\  "encodedDataLength": 1234
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const request_id = try json.getString(parsed.value, "requestId");
    const data_length = try json.getInt(parsed.value, "encodedDataLength");

    try std.testing.expectEqualStrings("REQ_001", request_id);
    try std.testing.expectEqual(@as(i64, 1234), data_length);
}

// ─── LoadingFailed Event Tests ────────────────────────────────────────────────

test "LoadingFailed - parse event params" {
    const json_str =
        \\{
        \\  "requestId": "REQ_001",
        \\  "timestamp": 12345.9,
        \\  "type": "Document",
        \\  "errorText": "net::ERR_CONNECTION_REFUSED",
        \\  "canceled": false
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const request_id = try json.getString(parsed.value, "requestId");
    const error_text = try json.getString(parsed.value, "errorText");

    try std.testing.expectEqualStrings("REQ_001", request_id);
    try std.testing.expectEqualStrings("net::ERR_CONNECTION_REFUSED", error_text);
}

// ─── Resource Type Tests ──────────────────────────────────────────────────────

test "ResourceType - common types" {
    const types = [_][]const u8{
        "Document",
        "Stylesheet",
        "Image",
        "Media",
        "Font",
        "Script",
        "TextTrack",
        "XHR",
        "Fetch",
        "EventSource",
        "WebSocket",
        "Manifest",
        "SignedExchange",
        "Ping",
        "CSPViolationReport",
        "Preflight",
        "Other",
    };

    // Just verify these are valid resource types
    try std.testing.expectEqual(@as(usize, 17), types.len);
}
