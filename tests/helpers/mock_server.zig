const std = @import("std");

/// Mock CDP WebSocket server for unit testing
pub const MockCDPServer = struct {
    allocator: std.mem.Allocator,
    listener: std.net.Server,
    port: u16,
    thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),

    // Expectations
    expectations: std.ArrayList(Expectation),
    expectations_mutex: std.Thread.Mutex,

    // Received commands
    received_commands: std.ArrayList(ReceivedCommand),
    received_mutex: std.Thread.Mutex,

    const Expectation = struct {
        method: []const u8,
        response_result: ?[]const u8 = null,
        response_error: ?ErrorPayload = null,
        delay_ms: u64 = 0,
    };

    const ErrorPayload = struct {
        code: i64,
        message: []const u8,
    };

    const ReceivedCommand = struct {
        method: []const u8,
        params: ?std.json.Value,
        id: u64,
    };

    const Self = @This();

    /// Start the mock server
    pub fn start(allocator: std.mem.Allocator) !*Self {
        const address = try std.net.Address.parseIp("127.0.0.1", 0);
        const listener = try address.listen(.{
            .reuse_address = true,
        });

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .listener = listener,
            .port = listener.listen_address.in.getPort(),
            .thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
            .expectations = std.ArrayList(Expectation).init(allocator),
            .expectations_mutex = .{},
            .received_commands = std.ArrayList(ReceivedCommand).init(allocator),
            .received_mutex = .{},
        };

        self.thread = try std.Thread.spawn(.{}, acceptLoop, .{self});

        return self;
    }

    /// Stop the mock server
    pub fn stop(self: *Self) void {
        self.should_stop.store(true, .monotonic);

        // Connect to self to unblock accept
        const address = std.net.Address.parseIp("127.0.0.1", self.port) catch return;
        const conn = std.net.tcpConnectToAddress(address) catch return;
        conn.close();

        if (self.thread) |t| {
            t.join();
        }

        self.listener.deinit();

        // Clean up expectations
        for (self.expectations.items) |exp| {
            self.allocator.free(exp.method);
            if (exp.response_result) |r| self.allocator.free(r);
            if (exp.response_error) |e| self.allocator.free(e.message);
        }
        self.expectations.deinit();

        // Clean up received commands
        for (self.received_commands.items) |cmd| {
            self.allocator.free(cmd.method);
        }
        self.received_commands.deinit();

        self.allocator.destroy(self);
    }

    /// Get WebSocket URL
    pub fn getWsUrl(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "ws://127.0.0.1:{}/devtools/browser/mock-guid", .{self.port});
    }

    /// Queue an expected command with response
    pub fn expectCommand(self: *Self, method: []const u8, result_json: []const u8) void {
        self.expectations_mutex.lock();
        defer self.expectations_mutex.unlock();

        self.expectations.append(.{
            .method = self.allocator.dupe(u8, method) catch return,
            .response_result = self.allocator.dupe(u8, result_json) catch return,
        }) catch return;
    }

    /// Queue an expected command with error response
    pub fn expectError(self: *Self, method: []const u8, code: i64, message: []const u8) void {
        self.expectations_mutex.lock();
        defer self.expectations_mutex.unlock();

        self.expectations.append(.{
            .method = self.allocator.dupe(u8, method) catch return,
            .response_error = .{
                .code = code,
                .message = self.allocator.dupe(u8, message) catch return,
            },
        }) catch return;
    }

    /// Verify all expectations were met
    pub fn verifyAllExpectationsMet(self: *Self) !void {
        self.expectations_mutex.lock();
        defer self.expectations_mutex.unlock();

        if (self.expectations.items.len > 0) {
            std.debug.print("Unmet expectations: {} remaining\n", .{self.expectations.items.len});
            return error.UnmetExpectations;
        }
    }

    /// Accept loop (runs in separate thread)
    fn acceptLoop(self: *Self) void {
        while (!self.should_stop.load(.monotonic)) {
            const conn = self.listener.accept() catch continue;
            defer conn.stream.close();

            self.handleClient(conn.stream) catch continue;
        }
    }

    /// Handle a client connection
    fn handleClient(self: *Self, stream: std.net.Stream) !void {
        // Perform WebSocket handshake
        try self.performWsHandshake(stream);

        // Handle messages
        var buf: [4096]u8 = undefined;
        while (!self.should_stop.load(.monotonic)) {
            // Read frame
            const n = stream.read(&buf) catch break;
            if (n == 0) break;

            // Parse frame (simplified - assumes text frame)
            if (n < 2) continue;

            const payload_len = @as(usize, buf[1] & 0x7F);
            var payload_start: usize = 2;

            if (payload_len == 126) {
                payload_start = 4;
            } else if (payload_len == 127) {
                payload_start = 10;
            }

            // Check for masked frame
            const masked = (buf[1] & 0x80) != 0;
            if (masked) {
                const mask_key = buf[payload_start..payload_start + 4];
                payload_start += 4;

                // Unmask
                for (buf[payload_start .. payload_start + payload_len], 0..) |*byte, i| {
                    byte.* ^= mask_key[i % 4];
                }
            }

            const payload = buf[payload_start .. payload_start + payload_len];

            // Parse command
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, payload, .{}) catch continue;
            defer parsed.deinit();

            const id = switch (parsed.value.object.get("id") orelse continue) {
                .integer => |i| @as(u64, @intCast(i)),
                else => continue,
            };

            const method = switch (parsed.value.object.get("method") orelse continue) {
                .string => |s| s,
                else => continue,
            };

            // Store received command
            self.received_mutex.lock();
            self.received_commands.append(.{
                .method = self.allocator.dupe(u8, method) catch unreachable,
                .params = parsed.value.object.get("params"),
                .id = id,
            }) catch {};
            self.received_mutex.unlock();

            // Find matching expectation
            self.expectations_mutex.lock();
            var response: ?[]const u8 = null;
            defer if (response) |r| self.allocator.free(r);

            for (self.expectations.items, 0..) |exp, i| {
                if (std.mem.eql(u8, exp.method, method)) {
                    if (exp.response_result) |result| {
                        response = std.fmt.allocPrint(self.allocator, "{{\"id\":{},\"result\":{}}}", .{ id, result }) catch null;
                    } else if (exp.response_error) |err| {
                        response = std.fmt.allocPrint(self.allocator, "{{\"id\":{},\"error\":{{\"code\":{},\"message\":\"{s}\"}}}}", .{ id, err.code, err.message }) catch null;
                    }
                    _ = self.expectations.orderedRemove(i);
                    break;
                }
            }
            self.expectations_mutex.unlock();

            // Send response
            if (response) |resp| {
                try self.sendTextFrame(stream, resp);
            } else {
                // Default empty response
                const default_resp = std.fmt.allocPrint(self.allocator, "{{\"id\":{},\"result\":{{}}}}", .{id}) catch return;
                defer self.allocator.free(default_resp);
                try self.sendTextFrame(stream, default_resp);
            }
        }
    }

    /// Perform WebSocket handshake
    fn performWsHandshake(self: *Self, stream: std.net.Stream) !void {
        _ = self;
        var buf: [1024]u8 = undefined;
        const n = stream.read(&buf) catch return error.HandshakeFailed;
        const request = buf[0..n];

        // Find WebSocket key
        const key_header = "Sec-WebSocket-Key: ";
        const key_start = std.mem.indexOf(u8, request, key_header) orelse return error.HandshakeFailed;
        const key_value_start = key_start + key_header.len;
        const key_end = std.mem.indexOf(u8, request[key_value_start..], "\r\n") orelse return error.HandshakeFailed;
        const key = request[key_value_start .. key_value_start + key_end];

        // Compute accept key
        const guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var input: [60]u8 = undefined;
        @memcpy(input[0..key.len], key);
        @memcpy(input[key.len..], guid);

        var sha1 = std.crypto.hash.Sha1.init(.{});
        sha1.update(input[0 .. key.len + guid.len]);
        var hash: [20]u8 = undefined;
        sha1.final(&hash);

        var accept_key: [28]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&accept_key, &hash);

        // Send response
        const response = std.fmt.bufPrint(&buf, "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n" ++
            "\r\n", .{&accept_key}) catch return error.HandshakeFailed;

        _ = stream.write(response) catch return error.HandshakeFailed;
    }

    /// Send a text frame
    fn sendTextFrame(self: *Self, stream: std.net.Stream, payload: []const u8) !void {
        _ = self;
        var header: [10]u8 = undefined;
        var header_len: usize = 2;

        header[0] = 0x81; // FIN + TEXT

        if (payload.len < 126) {
            header[1] = @truncate(payload.len);
        } else if (payload.len < 65536) {
            header[1] = 126;
            header[2] = @truncate(payload.len >> 8);
            header[3] = @truncate(payload.len);
            header_len = 4;
        } else {
            header[1] = 127;
            // Simplified - only support smaller payloads
            return error.PayloadTooLarge;
        }

        _ = stream.write(header[0..header_len]) catch return error.ConnectionClosed;
        _ = stream.write(payload) catch return error.ConnectionClosed;
    }
};

test "MockCDPServer start and stop" {
    var server = try MockCDPServer.start(std.testing.allocator);
    defer server.stop();

    try std.testing.expect(server.port > 0);
}

test "MockCDPServer getWsUrl" {
    var server = try MockCDPServer.start(std.testing.allocator);
    defer server.stop();

    const url = try server.getWsUrl(std.testing.allocator);
    defer std.testing.allocator.free(url);

    try std.testing.expect(std.mem.startsWith(u8, url, "ws://127.0.0.1:"));
}
