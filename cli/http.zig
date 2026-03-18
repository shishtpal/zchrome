const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");

/// Simple HTTP GET request result
pub const HttpResponse = struct {
    status_code: u16,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *HttpResponse) void {
        self.allocator.free(self.body);
    }
};

/// Perform a simple HTTP GET request
pub fn get(allocator: std.mem.Allocator, io: std.Io, host: []const u8, port: u16, path: []const u8) !HttpResponse {
    // Parse IP address using Zig 0.16 API
    const address = std.Io.net.IpAddress.parse(host, port) catch
        return error.ConnectionFailed;

    // TCP connect
    const stream = std.Io.net.IpAddress.connect(address, io, .{
        .mode = .stream,
        .protocol = .tcp,
    }) catch return error.ConnectionFailed;
    defer stream.close(io);

    // Build HTTP request
    const request = try std.fmt.allocPrint(allocator, "GET {s} HTTP/1.1\r\nHost: {s}:{}\r\nConnection: close\r\n\r\n", .{ path, host, port });
    defer allocator.free(request);

    // Send request using writer interface
    var write_buf: [4096]u8 = undefined;
    var writer = stream.writer(io, &write_buf);
    writer.interface.writeAll(request) catch return error.SendFailed;
    writer.interface.flush() catch return error.SendFailed;

    // Read response using reader interface
    var response_buf: std.ArrayList(u8) = .empty;
    errdefer response_buf.deinit(allocator);

    var read_buf: [4096]u8 = undefined;
    var reader = stream.reader(io, &read_buf);
    const max_response_size: usize = 64 * 1024;

    while (response_buf.items.len < max_response_size) {
        // Try to peek - will block until data available or connection closed
        const peeked = reader.interface.peek(1) catch break;
        if (peeked.len == 0) break;

        // Get all available data without blocking
        const chunk = reader.interface.peekGreedy(1) catch break;
        if (chunk.len == 0) break;

        try response_buf.appendSlice(allocator, chunk);
        reader.interface.toss(chunk.len);

        // Check if we have complete response
        if (std.mem.indexOf(u8, response_buf.items, "\r\n\r\n")) |header_end| {
            const headers = response_buf.items[0..header_end];
            // Look for Content-Length to know when body is complete
            if (std.mem.indexOf(u8, headers, "Content-Length:")) |cl_start| {
                const cl_line_start = cl_start + "Content-Length:".len;
                if (std.mem.indexOf(u8, headers[cl_line_start..], "\r\n")) |cl_line_end| {
                    const cl_str = std.mem.trim(u8, headers[cl_line_start..][0..cl_line_end], " ");
                    if (std.fmt.parseInt(usize, cl_str, 10)) |content_length| {
                        const body_start = header_end + 4;
                        if (response_buf.items.len >= body_start + content_length) break;
                    } else |_| {}
                }
            }
        }
    }

    // Parse response
    const response_data = response_buf.items;
    if (response_data.len == 0) return error.InvalidResponse;

    // Find end of headers
    const header_end = std.mem.indexOf(u8, response_data, "\r\n\r\n") orelse
        return error.InvalidResponse;

    // Parse status line (HTTP/1.1 200 OK)
    const first_line_end = std.mem.indexOf(u8, response_data, "\r\n") orelse
        return error.InvalidResponse;
    const status_line = response_data[0..first_line_end];

    // Find status code (after first space)
    const first_space = std.mem.indexOf(u8, status_line, " ") orelse
        return error.InvalidResponse;
    const after_space = status_line[first_space + 1 ..];
    const second_space = std.mem.indexOf(u8, after_space, " ") orelse after_space.len;
    const status_str = after_space[0..second_space];
    const status_code = std.fmt.parseInt(u16, status_str, 10) catch
        return error.InvalidResponse;

    // Extract body
    const body_start = header_end + 4;
    const body = try allocator.dupe(u8, response_data[body_start..]);
    response_buf.deinit(allocator);

    return .{
        .status_code = status_code,
        .body = body,
        .allocator = allocator,
    };
}

/// Query Chrome's /json/version endpoint to get WebSocket URL
pub fn getChromeWsUrl(allocator: std.mem.Allocator, io: std.Io, port: u16) ![]const u8 {
    // Try HTTP /json/version endpoint first (standard Chrome launch)
    if (get(allocator, io, "127.0.0.1", port, "/json/version")) |response_val| {
        var response = response_val;
        defer response.deinit();

        if (response.status_code == 200) {
            // Parse JSON response
            if (json.parse(allocator, response.body, .{})) |parsed_val| {
                var parsed = parsed_val;
                defer parsed.deinit(allocator);

                // Extract webSocketDebuggerUrl
                if (parsed.get("webSocketDebuggerUrl")) |ws_url| {
                    if (ws_url == .string) {
                        return allocator.dupe(u8, ws_url.string);
                    }
                }
            } else |_| {}
        }
    } else |_| {}

    // Fallback: Try direct WebSocket connection (Chrome 136+ inspect-based debugging)
    // This handles chrome://inspect/#remote-debugging which doesn't expose HTTP endpoints
    return tryDirectWsConnection(allocator, io, port);
}

/// Try direct WebSocket connection to Chrome's devtools/browser endpoint
/// Used as fallback for Chrome 136+ inspect-based debugging where /json/version returns 404
pub fn tryDirectWsConnection(allocator: std.mem.Allocator, io: std.Io, port: u16) ![]const u8 {
    const ws_url = try std.fmt.allocPrint(allocator, "ws://127.0.0.1:{}/devtools/browser", .{port});
    errdefer allocator.free(ws_url);

    // Try to connect and verify with Browser.getVersion
    var browser = cdp.Browser.connect(ws_url, allocator, io, .{}) catch {
        return error.ChromeNotResponding;
    };
    defer browser.disconnect();

    // Verify it's a valid CDP endpoint by getting version
    var version = browser.version() catch {
        return error.ChromeNotResponding;
    };
    version.deinit(allocator);

    std.debug.print("Note: Using direct WebSocket fallback (inspect-based debugging).\n", .{});
    std.debug.print("      For automation without prompts, use: chrome --remote-debugging-port={}\n", .{port});

    return ws_url;
}

/// Check if Chrome is running on the specified port
pub fn isChromeRunning(io: std.Io, port: u16) bool {
    const address = std.Io.net.IpAddress.parse("127.0.0.1", port) catch return false;

    const stream = std.Io.net.IpAddress.connect(address, io, .{
        .mode = .stream,
        .protocol = .tcp,
    }) catch return false;
    stream.close(io);
    return true;
}
