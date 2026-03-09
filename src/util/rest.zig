const std = @import("std");
const json = @import("json");
const zhttp = @import("zhttp");

/// HTTP method
pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,

    pub fn toString(self: Method) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .PATCH => "PATCH",
            .DELETE => "DELETE",
        };
    }
};

/// HTTP response
pub const Response = struct {
    status_code: u16,
    body: []const u8,
    allocator: std.mem.Allocator,

    // Internal: owned copy of body
    _body_owned: []const u8,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self._body_owned);
    }

    /// Parse response body as JSON
    pub fn parseJson(self: *const Response, allocator: std.mem.Allocator) !json.Value {
        return json.parse(allocator, self.body, .{});
    }
};

/// Request options
pub const RequestOptions = struct {
    allocator: std.mem.Allocator,
    init: std.process.Init,
    method: Method = .GET,
    /// Request body (for POST/PUT/PATCH)
    body: ?[]const u8 = null,
    /// Authorization bearer token
    bearer_token: ?[]const u8 = null,
    /// Content-Type header (default: application/json)
    content_type: []const u8 = "application/json",
    /// Request timeout in ms
    timeout_ms: u32 = 30_000,
};

pub const RestError = error{
    InvalidUrl,
    ConnectionFailed,
    SendFailed,
    ReceiveFailed,
    Timeout,
    InvalidResponse,
    TlsError,
    OutOfMemory,
    RequestFailed,
};

/// Perform an HTTP/HTTPS request using zhttp
pub fn request(url: []const u8, opts: RequestOptions) RestError!Response {
    const allocator = opts.allocator;

    // Build headers for bearer token
    var headers_buf: [1]zhttp.Header = undefined;
    var headers_slice: ?[]const zhttp.Header = null;

    // We need to build Authorization header if bearer_token is provided
    var auth_value_buf: ?[]u8 = null;
    defer if (auth_value_buf) |buf| allocator.free(buf);

    if (opts.bearer_token) |token| {
        auth_value_buf = std.fmt.allocPrint(allocator, "Bearer {s}", .{token}) catch
            return RestError.OutOfMemory;
        headers_buf[0] = .{ .name = "Authorization", .value = auth_value_buf.? };
        headers_slice = &headers_buf;
    }

    const zhttp_opts = zhttp.RequestOptions{
        .headers = headers_slice,
        .timeout_milliseconds = opts.timeout_ms,
    };

    // Call appropriate zhttp function based on method
    const body = opts.body orelse "";
    const zhttp_response = switch (opts.method) {
        .GET => zhttp.sendGetRequestWithOptions(opts.init, allocator, url, zhttp_opts),
        .POST => zhttp.sendPostRequestWithOptions(opts.init, allocator, url, body, opts.content_type, zhttp_opts),
        .PUT => zhttp.sendPutRequestWithOptions(opts.init, allocator, url, body, opts.content_type, zhttp_opts),
        .PATCH => zhttp.sendPatchRequestWithOptions(opts.init, allocator, url, body, opts.content_type, zhttp_opts),
        .DELETE => zhttp.sendDeleteRequestWithOptions(opts.init, allocator, url, zhttp_opts),
    } catch |err| {
        return mapHttpError(err);
    };

    // Duplicate the body since zhttp.Response.deinit() will free it
    const body_copy = allocator.dupe(u8, zhttp_response.body) catch {
        var resp = zhttp_response;
        resp.deinit();
        return RestError.OutOfMemory;
    };

    // Free the zhttp response (we've copied what we need)
    var resp = zhttp_response;
    resp.deinit();

    return Response{
        .status_code = zhttp_response.status_code,
        .body = body_copy,
        .allocator = allocator,
        ._body_owned = body_copy,
    };
}

fn mapHttpError(err: zhttp.HttpRequestError) RestError {
    return switch (err) {
        zhttp.HttpRequestError.InvalidUrl => RestError.InvalidUrl,
        zhttp.HttpRequestError.ConnectionFailed,
        zhttp.HttpRequestError.ConnectionRefused,
        zhttp.HttpRequestError.ConnectionResetByPeer,
        => RestError.ConnectionFailed,
        zhttp.HttpRequestError.TlsHandshakeFailed,
        zhttp.HttpRequestError.TlsAlertReceived,
        zhttp.HttpRequestError.TlsCertificateVerificationFailed,
        => RestError.TlsError,
        zhttp.HttpRequestError.ConnectionTimedOut => RestError.Timeout,
        zhttp.HttpRequestError.OutOfMemory => RestError.OutOfMemory,
        else => RestError.RequestFailed,
    };
}

/// Helper to build JSON request body
pub fn jsonBody(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return json.serializeAlloc(allocator, value);
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "Method.toString returns correct strings" {
    try std.testing.expectEqualStrings("GET", Method.GET.toString());
    try std.testing.expectEqualStrings("POST", Method.POST.toString());
    try std.testing.expectEqualStrings("DELETE", Method.DELETE.toString());
}
