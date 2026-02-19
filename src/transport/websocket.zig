const std = @import("std");

/// WebSocket opcodes (RFC 6455)
pub const OPCODE_CONTINUATION: u4 = 0x0;
pub const OPCODE_TEXT: u4 = 0x1;
pub const OPCODE_BINARY: u4 = 0x2;
pub const OPCODE_CLOSE: u4 = 0x8;
pub const OPCODE_PING: u4 = 0x9;
pub const OPCODE_PONG: u4 = 0xA;

/// Maximum payload size for control frames
pub const MAX_CONTROL_FRAME_PAYLOAD = 125;

/// Default maximum message size (16 MB for screenshots)
pub const DEFAULT_MAX_MESSAGE_SIZE = 16 * 1024 * 1024;

/// WebSocket connection errors
pub const WebSocketError = error{
    ConnectionRefused,
    ConnectionClosed,
    ConnectionReset,
    HandshakeFailed,
    TlsError,
    FrameTooLarge,
    InvalidFrame,
    Timeout,
    InvalidUrl,
    InvalidResponse,
    OutOfMemory,
    NotImplemented,
};

/// Received message
pub const Message = struct {
    opcode: u4,
    data: []const u8,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// WebSocket client options
pub const Options = struct {
    host: []const u8,
    port: u16,
    path: []const u8 = "/",
    tls: bool = false,
    connect_timeout_ms: u32 = 10_000,
    max_message_size: usize = DEFAULT_MAX_MESSAGE_SIZE,
    allocator: std.mem.Allocator,
    io: std.Io,
};

/// WebSocket client (RFC 6455)
pub const WebSocket = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    max_message_size: usize,
    is_closed: bool,
    stream: std.Io.net.Stream,
    read_buf: [8192]u8,
    write_buf: [8192]u8,

    const Self = @This();

    /// Connect to a WebSocket server
    pub fn connect(opts: Options) WebSocketError!Self {
        // Parse IP address
        const address = std.Io.net.IpAddress.parse(opts.host, opts.port) catch
            return WebSocketError.InvalidUrl;

        // TCP connect using new Io API
        const stream = std.Io.net.IpAddress.connect(address, opts.io, .{
            .mode = .stream,
            .protocol = .tcp,
        }) catch return WebSocketError.ConnectionRefused;
        errdefer stream.close(opts.io);

        // Initialize PRNG for mask key generation
        var seed_state: u64 = 0x853c49e6748fea9b;
        seed_state ^= @intFromPtr(&opts);
        var prng = std.Random.DefaultPrng.init(seed_state);

        // Generate WebSocket key
        var key_bytes: [16]u8 = undefined;
        prng.random().bytes(&key_bytes);
        var key_buf: [24]u8 = undefined;
        const key_encoded = std.base64.standard.Encoder.encode(&key_buf, &key_bytes);

        // Build HTTP upgrade request
        const request = std.fmt.allocPrint(opts.allocator,
            "GET {s} HTTP/1.1\r\n" ++
                "Host: {s}:{d}\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Key: {s}\r\n" ++
                "Sec-WebSocket-Version: 13\r\n" ++
                "\r\n", .{ opts.path, opts.host, opts.port, key_encoded }) catch
            return WebSocketError.OutOfMemory;
        defer opts.allocator.free(request);

        // Write using Stream.writer
        var write_buf_temp: [4096]u8 = undefined;
        var writer = stream.writer(opts.io, &write_buf_temp);
        writer.interface.writeAll(request) catch return WebSocketError.HandshakeFailed;
        writer.interface.flush() catch return WebSocketError.HandshakeFailed;

        // Read response using Stream.reader
        var read_buf_temp: [4096]u8 = undefined;
        var reader = stream.reader(opts.io, &read_buf_temp);

        // Read until we get the full HTTP response headers
        var response_buf: [1024]u8 = undefined;
        var response_len: usize = 0;

        while (response_len < response_buf.len) {
            const chunk = reader.interface.peek(1) catch return WebSocketError.HandshakeFailed;
            if (chunk.len == 0) return WebSocketError.HandshakeFailed;

            response_buf[response_len] = chunk[0];
            _ = reader.interface.discard(.limited(1)) catch return WebSocketError.HandshakeFailed;
            response_len += 1;

            // Check for end of headers
            if (response_len >= 4 and
                response_buf[response_len - 4] == '\r' and
                response_buf[response_len - 3] == '\n' and
                response_buf[response_len - 2] == '\r' and
                response_buf[response_len - 1] == '\n')
            {
                break;
            }
        }

        const response = response_buf[0..response_len];

        // Verify 101 Switching Protocols
        if (!std.mem.startsWith(u8, response, "HTTP/1.1 101")) {
            return WebSocketError.HandshakeFailed;
        }

        return .{
            .allocator = opts.allocator,
            .io = opts.io,
            .max_message_size = opts.max_message_size,
            .is_closed = false,
            .stream = stream,
            .read_buf = undefined,
            .write_buf = undefined,
        };
    }

    /// Send a text message
    pub fn sendText(self: *Self, payload: []const u8) WebSocketError!void {
        var writer = self.stream.writer(self.io, &self.write_buf);

        // Build WebSocket frame header
        var frame_buf: [14]u8 = undefined;
        var frame_len: usize = 2;

        // FIN + TEXT opcode
        frame_buf[0] = 0x80 | @as(u8, OPCODE_TEXT);

        // Mask bit set + payload length
        if (payload.len < 126) {
            frame_buf[1] = 0x80 | @as(u8, @truncate(payload.len));
        } else if (payload.len < 65536) {
            frame_buf[1] = 0x80 | 126;
            frame_buf[2] = @truncate(payload.len >> 8);
            frame_buf[3] = @truncate(payload.len);
            frame_len = 4;
        } else {
            frame_buf[1] = 0x80 | 127;
            @memset(frame_buf[2..6], 0);
            frame_buf[6] = @truncate(payload.len >> 24);
            frame_buf[7] = @truncate(payload.len >> 16);
            frame_buf[8] = @truncate(payload.len >> 8);
            frame_buf[9] = @truncate(payload.len);
            frame_len = 10;
        }

        // Add mask key (using simple counter)
        const mask_key = [4]u8{ 0x12, 0x34, 0x56, 0x78 };
        @memcpy(frame_buf[frame_len..][0..4], &mask_key);
        frame_len += 4;

        // Send frame header
        writer.interface.writeAll(frame_buf[0..frame_len]) catch return WebSocketError.ConnectionClosed;

        // Send masked payload
        if (payload.len > 0) {
            const masked = self.allocator.dupe(u8, payload) catch
                return WebSocketError.OutOfMemory;
            defer self.allocator.free(masked);

            for (masked, 0..) |*byte, i| {
                byte.* ^= mask_key[i % 4];
            }

            writer.interface.writeAll(masked) catch return WebSocketError.ConnectionClosed;
        }

        writer.interface.flush() catch return WebSocketError.ConnectionClosed;
    }

    /// Receive a complete message
    pub fn receiveMessage(self: *Self) WebSocketError!Message {
        var reader = self.stream.reader(self.io, &self.read_buf);

        // Read frame header (2 bytes)
        var header: [2]u8 = undefined;
        for (&header) |*byte| {
            const chunk = reader.interface.peek(1) catch return WebSocketError.ConnectionClosed;
            if (chunk.len == 0) return WebSocketError.ConnectionClosed;
            byte.* = chunk[0];
            _ = reader.interface.discard(.limited(1)) catch return WebSocketError.ConnectionClosed;
        }

        const fin = (header[0] & 0x80) != 0;
        _ = fin;
        const opcode: u4 = @truncate(header[0] & 0x0F);
        const masked = (header[1] & 0x80) != 0;
        var payload_len: usize = header[1] & 0x7F;

        // Extended payload length
        if (payload_len == 126) {
            var ext: [2]u8 = undefined;
            for (&ext) |*byte| {
                const chunk = reader.interface.peek(1) catch return WebSocketError.ConnectionClosed;
                if (chunk.len == 0) return WebSocketError.ConnectionClosed;
                byte.* = chunk[0];
                _ = reader.interface.discard(.limited(1)) catch return WebSocketError.ConnectionClosed;
            }
            payload_len = (@as(usize, ext[0]) << 8) | ext[1];
        } else if (payload_len == 127) {
            var ext: [8]u8 = undefined;
            for (&ext) |*byte| {
                const chunk = reader.interface.peek(1) catch return WebSocketError.ConnectionClosed;
                if (chunk.len == 0) return WebSocketError.ConnectionClosed;
                byte.* = chunk[0];
                _ = reader.interface.discard(.limited(1)) catch return WebSocketError.ConnectionClosed;
            }
            payload_len = (@as(usize, ext[4]) << 24) |
                (@as(usize, ext[5]) << 16) |
                (@as(usize, ext[6]) << 8) | ext[7];
        }

        if (payload_len > self.max_message_size) {
            return WebSocketError.FrameTooLarge;
        }

        // Read mask key if present
        var mask_key: [4]u8 = [_]u8{ 0, 0, 0, 0 };
        if (masked) {
            for (&mask_key) |*byte| {
                const chunk = reader.interface.peek(1) catch return WebSocketError.ConnectionClosed;
                if (chunk.len == 0) return WebSocketError.ConnectionClosed;
                byte.* = chunk[0];
                _ = reader.interface.discard(.limited(1)) catch return WebSocketError.ConnectionClosed;
            }
        }

        // Read payload
        const payload = self.allocator.alloc(u8, payload_len) catch
            return WebSocketError.OutOfMemory;
        errdefer self.allocator.free(payload);

        var bytes_read: usize = 0;
        while (bytes_read < payload_len) {
            const chunk = reader.interface.peek(payload_len - bytes_read) catch {
                self.allocator.free(payload);
                return WebSocketError.ConnectionClosed;
            };
            if (chunk.len == 0) {
                self.allocator.free(payload);
                return WebSocketError.ConnectionClosed;
            }
            const to_copy = @min(chunk.len, payload_len - bytes_read);
            @memcpy(payload[bytes_read..][0..to_copy], chunk[0..to_copy]);
            _ = reader.interface.discard(.limited(to_copy)) catch {
                self.allocator.free(payload);
                return WebSocketError.ConnectionClosed;
            };
            bytes_read += to_copy;
        }

        // Unmask if needed
        if (masked) {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask_key[i % 4];
            }
        }

        return .{
            .opcode = opcode,
            .data = payload,
        };
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        self.stream.close(self.io);
        self.is_closed = true;
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────────

test "computeAcceptKey" {
    const guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    var input: [60]u8 = undefined;
    @memcpy(input[0..key.len], key);
    @memcpy(input[key.len..][0..guid.len], guid);

    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(input[0 .. key.len + guid.len]);
    var hash: [20]u8 = undefined;
    sha1.final(&hash);

    var result: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&result, &hash);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &result);
}
