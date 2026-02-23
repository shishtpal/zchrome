//! Minimal WebSocket server for local event streaming.
//!
//! Uses std.Io.net async API for network operations.

const std = @import("std");
const ws = @import("websocket.zig");

pub const ServerError = error{
    BindFailed,
    AcceptFailed,
    HandshakeFailed,
    ConnectionClosed,
    FrameTooLarge,
    InvalidFrame,
    OutOfMemory,
    WouldBlock,
};

/// A connected WebSocket client
pub const Client = struct {
    stream: std.Io.net.Stream,
    io: std.Io,
    allocator: std.mem.Allocator,
    read_buf: [4096]u8,
    write_buf: [1024]u8,
    persistent_reader: ?std.Io.net.Stream.Reader,
    is_closed: bool,

    const Self = @This();

    /// Read exactly `len` bytes
    fn readBytes(self: *Self, dest: []u8) ServerError!void {
        if (self.persistent_reader == null) {
            self.persistent_reader = self.stream.reader(self.io, &self.read_buf);
        }
        var r = &self.persistent_reader.?;
        var filled: usize = 0;
        while (filled < dest.len) {
            _ = r.interface.peek(1) catch return ServerError.ConnectionClosed;
            const chunk = r.interface.peekGreedy(1) catch return ServerError.ConnectionClosed;
            const remaining = dest.len - filled;
            const n = @min(chunk.len, remaining);
            @memcpy(dest[filled..][0..n], chunk[0..n]);
            r.interface.toss(n);
            filled += n;
        }
    }

    /// Read a WebSocket frame (clients send masked frames)
    pub fn readFrame(self: *Self) ServerError!struct { opcode: u4, data: []u8 } {
        var header: [2]u8 = undefined;
        try self.readBytes(&header);

        const opcode: u4 = @truncate(header[0] & 0x0F);
        const masked = (header[1] & 0x80) != 0;
        var payload_len: usize = header[1] & 0x7F;

        if (payload_len == 126) {
            var ext: [2]u8 = undefined;
            try self.readBytes(&ext);
            payload_len = (@as(usize, ext[0]) << 8) | ext[1];
        } else if (payload_len == 127) {
            var ext: [8]u8 = undefined;
            try self.readBytes(&ext);
            payload_len = (@as(usize, ext[4]) << 24) |
                (@as(usize, ext[5]) << 16) |
                (@as(usize, ext[6]) << 8) | ext[7];
        }

        if (payload_len > 64 * 1024) {
            return ServerError.FrameTooLarge;
        }

        var mask_key: [4]u8 = .{ 0, 0, 0, 0 };
        if (masked) {
            try self.readBytes(&mask_key);
        }

        const payload = self.allocator.alloc(u8, payload_len) catch
            return ServerError.OutOfMemory;
        errdefer self.allocator.free(payload);

        self.readBytes(payload) catch |err| {
            self.allocator.free(payload);
            return err;
        };

        if (masked) {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask_key[i % 4];
            }
        }

        return .{ .opcode = opcode, .data = payload };
    }

    /// Send a text frame (server doesn't mask)
    pub fn sendText(self: *Self, payload: []const u8) ServerError!void {
        var writer = self.stream.writer(self.io, &self.write_buf);
        var frame: [10]u8 = undefined;
        var len: usize = 2;

        frame[0] = 0x80 | @as(u8, ws.OPCODE_TEXT);
        if (payload.len < 126) {
            frame[1] = @truncate(payload.len);
        } else {
            frame[1] = 126;
            frame[2] = @truncate(payload.len >> 8);
            frame[3] = @truncate(payload.len);
            len = 4;
        }

        writer.interface.writeAll(frame[0..len]) catch return ServerError.ConnectionClosed;
        writer.interface.writeAll(payload) catch return ServerError.ConnectionClosed;
        writer.interface.flush() catch return ServerError.ConnectionClosed;
    }

    pub fn close(self: *Self) void {
        if (!self.is_closed) {
            // Send close frame
            var writer = self.stream.writer(self.io, &self.write_buf);
            writer.interface.writeAll(&[_]u8{ 0x88, 0x00 }) catch {};
            writer.interface.flush() catch {};
            self.stream.close(self.io);
            self.is_closed = true;
        }
    }
};

/// WebSocket server
pub const Server = struct {
    server: std.Io.net.Server,
    io: std.Io,
    allocator: std.mem.Allocator,
    port: u16,

    const Self = @This();

    /// Start server on specified port (localhost only)
    pub fn init(allocator: std.mem.Allocator, io: std.Io, port: u16) ServerError!Self {
        const addr = std.Io.net.IpAddress.parse("127.0.0.1", port) catch
            return ServerError.BindFailed;

        const server = std.Io.net.IpAddress.listen(addr, io, .{
            .reuse_address = true,
        }) catch return ServerError.BindFailed;

        return .{
            .server = server,
            .io = io,
            .allocator = allocator,
            .port = port,
        };
    }

    /// Accept a connection and perform WebSocket handshake
    pub fn accept(self: *Self) ServerError!Client {
        const stream = self.server.accept(self.io) catch
            return ServerError.AcceptFailed;
        errdefer stream.close(self.io);

        // Perform WebSocket handshake
        var read_buf: [2048]u8 = undefined;
        var reader = stream.reader(self.io, &read_buf);

        var request_buf: [2048]u8 = undefined;
        var request_len: usize = 0;

        // Read until \r\n\r\n
        while (request_len < request_buf.len - 4) {
            const b = reader.interface.takeByte() catch
                return ServerError.HandshakeFailed;
            request_buf[request_len] = b;
            request_len += 1;

            if (request_len >= 4 and
                request_buf[request_len - 4] == '\r' and
                request_buf[request_len - 3] == '\n' and
                request_buf[request_len - 2] == '\r' and
                request_buf[request_len - 1] == '\n')
            {
                break;
            }
        }

        // Extract Sec-WebSocket-Key
        const request = request_buf[0..request_len];
        const key = extractWebSocketKey(request) orelse
            return ServerError.HandshakeFailed;

        // Compute and send accept response
        const accept_key = computeAcceptKey(key);
        const response = std.fmt.allocPrint(self.allocator,
            "HTTP/1.1 101 Switching Protocols\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Accept: {s}\r\n" ++
                "\r\n", .{accept_key}) catch return ServerError.OutOfMemory;
        defer self.allocator.free(response);

        var write_buf: [512]u8 = undefined;
        var writer = stream.writer(self.io, &write_buf);
        writer.interface.writeAll(response) catch return ServerError.HandshakeFailed;
        writer.interface.flush() catch return ServerError.HandshakeFailed;

        return .{
            .stream = stream,
            .io = self.io,
            .allocator = self.allocator,
            .read_buf = undefined,
            .write_buf = undefined,
            .persistent_reader = null,
            .is_closed = false,
        };
    }

    pub fn close(self: *Self) void {
        self.server.deinit(self.io);
    }
};

fn extractWebSocketKey(request: []const u8) ?[]const u8 {
    const needle = "Sec-WebSocket-Key: ";
    const start = std.mem.indexOf(u8, request, needle) orelse return null;
    const key_start = start + needle.len;
    const end = std.mem.indexOfPos(u8, request, key_start, "\r\n") orelse return null;
    return request[key_start..end];
}

fn computeAcceptKey(key: []const u8) [28]u8 {
    const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(key);
    hasher.update(magic);
    const hash = hasher.finalResult();

    var result: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&result, &hash);
    return result;
}
