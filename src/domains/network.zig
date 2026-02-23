const std = @import("std");
const Session = @import("../core/session.zig").Session;
const json_util = @import("../util/json.zig");

/// Network domain client
pub const Network = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable network domain
    pub fn enable(self: *Self) !void {
        _ = try self.session.sendCommand("Network.enable", .{});
    }

    /// Disable network domain
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("Network.disable", .{});
    }

    /// Get response body for a given request
    pub fn getResponseBody(self: *Self, allocator: std.mem.Allocator, request_id: []const u8) !ResponseBody {
        const result = try self.session.sendCommand("Network.getResponseBody", .{
            .requestId = request_id,
        });

        return .{
            .body = try allocator.dupe(u8, try json_util.getString(result, "body")),
            .base64_encoded = try json_util.getBool(result, "base64Encoded"),
        };
    }

    /// Get request POST data
    pub fn getRequestPostData(self: *Self, allocator: std.mem.Allocator, request_id: []const u8) ![]const u8 {
        const result = try self.session.sendCommand("Network.getRequestPostData", .{
            .requestId = request_id,
        });
        return try allocator.dupe(u8, try json_util.getString(result, "postData"));
    }

    /// Set request interception (deprecated, use Fetch domain instead)
    pub fn setRequestInterception(self: *Self, patterns: []const RequestPattern) !void {
        _ = try self.session.sendCommand("Network.setRequestInterception", .{
            .patterns = patterns,
        });
    }

    /// Continue intercepted request
    pub fn continueInterceptedRequest(self: *Self, interception_id: []const u8, opts: ContinueInterceptedRequestOptions) !void {
        _ = try self.session.sendCommand("Network.continueInterceptedRequest", .{
            .interceptionId = interception_id,
            .errorReason = opts.error_reason,
            .rawResponse = opts.raw_response,
            .url = opts.url,
            .method = opts.method,
            .postData = opts.post_data,
            .headers = opts.headers,
        });
    }

    /// Set cache disabled
    pub fn setCacheDisabled(self: *Self, disabled: bool) !void {
        _ = try self.session.sendCommand("Network.setCacheDisabled", .{
            .cacheDisabled = disabled,
        });
    }

    /// Clear browser cache
    pub fn clearBrowserCache(self: *Self) !void {
        _ = try self.session.sendCommand("Network.clearBrowserCache", .{});
    }

    /// Clear browser cookies
    pub fn clearBrowserCookies(self: *Self) !void {
        _ = try self.session.sendCommand("Network.clearBrowserCookies", .{});
    }

    /// Set extra HTTP headers to be sent with every request
    pub fn setExtraHTTPHeaders(self: *Self, headers: std.json.Value) !void {
        _ = try self.session.sendCommand("Network.setExtraHTTPHeaders", .{
            .headers = headers,
        });
    }

    /// Emulate network conditions (offline, latency, throughput)
    pub fn emulateNetworkConditions(self: *Self, opts: NetworkConditions) !void {
        _ = try self.session.sendCommand("Network.emulateNetworkConditions", .{
            .offline = opts.offline,
            .latency = opts.latency,
            .downloadThroughput = opts.download_throughput,
            .uploadThroughput = opts.upload_throughput,
            .connectionType = opts.connection_type,
        });
    }

    /// Enable network tracking, network events will now be delivered to the client
    pub fn enableWithOptions(self: *Self, opts: EnableOptions) !void {
        _ = try self.session.sendCommand("Network.enable", .{
            .maxTotalBufferSize = opts.max_total_buffer_size,
            .maxResourceBufferSize = opts.max_resource_buffer_size,
            .maxPostDataSize = opts.max_post_data_size,
        });
    }

    /// Set blocked URLs (requests to these URLs will fail)
    pub fn setBlockedURLs(self: *Self, urls: []const []const u8) !void {
        _ = try self.session.sendCommand("Network.setBlockedURLs", .{
            .urls = urls,
        });
    }

    /// Replay XHR request
    pub fn replayXHR(self: *Self, request_id: []const u8) !void {
        _ = try self.session.sendCommand("Network.replayXHR", .{
            .requestId = request_id,
        });
    }

    /// Search for content in response body
    pub fn searchInResponseBody(
        self: *Self,
        allocator: std.mem.Allocator,
        request_id: []const u8,
        query: []const u8,
        case_sensitive: bool,
        is_regex: bool,
    ) ![]SearchMatch {
        const result = try self.session.sendCommand("Network.searchInResponseBody", .{
            .requestId = request_id,
            .query = query,
            .caseSensitive = case_sensitive,
            .isRegex = is_regex,
        });

        const matches_val = result.object.get("result") orelse return &[_]SearchMatch{};
        if (matches_val != .array) return &[_]SearchMatch{};

        var matches = std.ArrayList(SearchMatch).init(allocator);
        errdefer matches.deinit();

        for (matches_val.array.items) |item| {
            if (item != .object) continue;
            try matches.append(.{
                .line_number = if (item.object.get("lineNumber")) |v| (if (v == .integer) @intCast(v.integer) else 0) else 0,
                .line_content = if (item.object.get("lineContent")) |v| (if (v == .string) try allocator.dupe(u8, v.string) else "") else "",
            });
        }
        return try matches.toOwnedSlice();
    }

    /// Get security isolation status
    pub fn getSecurityIsolationStatus(self: *Self, allocator: std.mem.Allocator, frame_id: ?[]const u8) !SecurityIsolationStatus {
        const result = try self.session.sendCommand("Network.getSecurityIsolationStatus", .{
            .frameId = frame_id,
        });
        _ = allocator;
        return .{
            .coop = if (result.object.get("coop")) |v| v else null,
            .coep = if (result.object.get("coep")) |v| v else null,
        };
    }

    /// Load network resource (for service worker)
    pub fn loadNetworkResource(
        self: *Self,
        allocator: std.mem.Allocator,
        frame_id: ?[]const u8,
        url: []const u8,
        opts: LoadNetworkResourceOptions,
    ) !LoadedResource {
        const result = try self.session.sendCommand("Network.loadNetworkResource", .{
            .frameId = frame_id,
            .url = url,
            .options = .{
                .disableCache = opts.disable_cache,
                .includeCredentials = opts.include_credentials,
            },
        });

        const resource = result.object.get("resource") orelse return error.InvalidResponse;
        if (resource != .object) return error.InvalidResponse;

        return .{
            .success = if (resource.object.get("success")) |v| (if (v == .bool) v.bool else false) else false,
            .http_status_code = if (resource.object.get("httpStatusCode")) |v| (if (v == .integer) @intCast(v.integer) else 0) else 0,
            .net_error = if (resource.object.get("netError")) |v| (if (v == .integer) @intCast(v.integer) else null) else null,
            .net_error_name = if (resource.object.get("netErrorName")) |v| (if (v == .string) try allocator.dupe(u8, v.string) else null) else null,
            .stream = if (resource.object.get("stream")) |v| (if (v == .string) try allocator.dupe(u8, v.string) else null) else null,
        };
    }
};

// ─── Options Structs ────────────────────────────────────────────────────────

pub const NetworkConditions = struct {
    offline: bool = false,
    latency: f64 = 0,
    download_throughput: f64 = -1,
    upload_throughput: f64 = -1,
    connection_type: ?[]const u8 = null, // none, cellular2g, cellular3g, cellular4g, bluetooth, ethernet, wifi, wimax, other
};

pub const EnableOptions = struct {
    max_total_buffer_size: ?i64 = null,
    max_resource_buffer_size: ?i64 = null,
    max_post_data_size: ?i64 = null,
};

pub const ContinueInterceptedRequestOptions = struct {
    error_reason: ?[]const u8 = null,
    raw_response: ?[]const u8 = null,
    url: ?[]const u8 = null,
    method: ?[]const u8 = null,
    post_data: ?[]const u8 = null,
    headers: ?std.json.Value = null,
};

pub const LoadNetworkResourceOptions = struct {
    disable_cache: bool = false,
    include_credentials: bool = false,
};

// ─── Response Types ─────────────────────────────────────────────────────────

/// Response body
pub const ResponseBody = struct {
    body: []const u8,
    base64_encoded: bool,

    pub fn deinit(self: *ResponseBody, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

/// Search match result
pub const SearchMatch = struct {
    line_number: i64,
    line_content: []const u8,

    pub fn deinit(self: *SearchMatch, allocator: std.mem.Allocator) void {
        if (self.line_content.len > 0) allocator.free(self.line_content);
    }
};

/// Security isolation status
pub const SecurityIsolationStatus = struct {
    coop: ?std.json.Value = null,
    coep: ?std.json.Value = null,
};

/// Loaded resource result
pub const LoadedResource = struct {
    success: bool,
    http_status_code: i64,
    net_error: ?i64 = null,
    net_error_name: ?[]const u8 = null,
    stream: ?[]const u8 = null,

    pub fn deinit(self: *LoadedResource, allocator: std.mem.Allocator) void {
        if (self.net_error_name) |n| allocator.free(n);
        if (self.stream) |s| allocator.free(s);
    }
};

/// Request pattern for interception
pub const RequestPattern = struct {
    url_pattern: ?[]const u8 = null,
    resource_type: ?[]const u8 = null,
    interception_stage: ?[]const u8 = null,
};

/// Resource type enum
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

/// Request information
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

/// Network response
pub const Response = struct {
    url: []const u8,
    status: i64,
    status_text: []const u8,
    headers: std.json.Value,
    mime_type: []const u8,
    charset: ?[]const u8 = null,
    request_headers: ?std.json.Value = null,
    connection_reused: ?bool = null,
    connection_id: ?f64 = null,
    remote_ip_address: ?[]const u8 = null,
    remote_port: ?i64 = null,
    from_disk_cache: ?bool = null,
    from_service_worker: ?bool = null,
    from_prefetch_cache: ?bool = null,
    encoded_data_length: ?f64 = null,
    protocol: ?[]const u8 = null,
    security_state: ?[]const u8 = null,
};

// ─── Event Types ────────────────────────────────────────────────────────────

pub const RequestWillBeSent = struct {
    request_id: []const u8,
    loader_id: []const u8,
    document_url: []const u8,
    request: Request,
    timestamp: f64,
    wall_time: ?f64 = null,
    initiator: ?std.json.Value = null,
    redirect_has_extra_info: ?bool = null,
    redirect_response: ?Response = null,
    type: ?[]const u8 = null,
    frame_id: ?[]const u8 = null,
    has_user_gesture: ?bool = null,
};

pub const ResponseReceived = struct {
    request_id: []const u8,
    loader_id: []const u8,
    timestamp: f64,
    type: []const u8,
    response: Response,
    has_extra_info: ?bool = null,
    frame_id: ?[]const u8 = null,
};

pub const LoadingFinished = struct {
    request_id: []const u8,
    timestamp: f64,
    encoded_data_length: f64,
};

pub const LoadingFailed = struct {
    request_id: []const u8,
    timestamp: f64,
    type: []const u8,
    error_text: []const u8,
    canceled: ?bool = null,
    blocked_reason: ?[]const u8 = null,
    cors_error_status: ?std.json.Value = null,
};

pub const RequestIntercepted = struct {
    interception_id: []const u8,
    request: Request,
    frame_id: []const u8,
    resource_type: []const u8,
    is_navigation_request: bool,
    is_download: ?bool = null,
    redirect_url: ?[]const u8 = null,
    auth_challenge: ?std.json.Value = null,
    response_error_reason: ?[]const u8 = null,
    response_status_code: ?i64 = null,
    response_headers: ?std.json.Value = null,
};

pub const DataReceived = struct {
    request_id: []const u8,
    timestamp: f64,
    data_length: i64,
    encoded_data_length: i64,
};

pub const WebSocketCreated = struct {
    request_id: []const u8,
    url: []const u8,
    initiator: ?std.json.Value = null,
};

pub const WebSocketClosed = struct {
    request_id: []const u8,
    timestamp: f64,
};

pub const WebSocketFrameReceived = struct {
    request_id: []const u8,
    timestamp: f64,
    response: WebSocketFrame,
};

pub const WebSocketFrameSent = struct {
    request_id: []const u8,
    timestamp: f64,
    response: WebSocketFrame,
};

pub const WebSocketFrame = struct {
    opcode: f64,
    mask: bool,
    payload_data: []const u8,
};

pub const EventSourceMessageReceived = struct {
    request_id: []const u8,
    timestamp: f64,
    event_name: []const u8,
    event_id: []const u8,
    data: []const u8,
};
