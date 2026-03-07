//! Live streaming server module.
//!
//! Provides HTTP MJPEG streaming and WebSocket connections for
//! live viewing and interactive control of replay sessions.

const std = @import("std");
const cdp = @import("cdp");
const frame_capture = @import("frame_capture.zig");
const Frame = frame_capture.Frame;

/// Stream server configuration
pub const StreamConfig = struct {
    port: u16 = 8080,
    interactive: bool = false,
    max_clients: u32 = 10,
    jpeg_quality: u8 = 70,
};

/// Input event from viewer (for interactive mode)
pub const ViewerInput = struct {
    input_type: InputType,
    x: ?i32 = null,
    y: ?i32 = null,
    button: ?[]const u8 = null,
    key: ?[]const u8 = null,

    pub const InputType = enum {
        click,
        mousemove,
        keydown,
        keyup,
        scroll,
    };
};

/// Input callback type
pub const InputCallback = *const fn (input: ViewerInput, ctx: ?*anyopaque) void;

/// Client connection
const StreamClient = struct {
    stream: std.Io.net.Stream,
    mode: ClientMode,
    active: bool = true,
    read_buf: [4096]u8 = undefined,
    write_buf: [1024]u8 = undefined,

    const ClientMode = enum {
        mjpeg,
        websocket,
        http,
    };
};

/// Stream server for live viewing
pub const StreamServer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: StreamConfig,

    // Server state
    server: ?std.Io.net.Server = null,
    clients: std.ArrayList(StreamClient),
    server_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool),

    // Interactive callbacks
    input_callback: ?InputCallback = null,
    input_ctx: ?*anyopaque = null,

    // Frame buffer for new clients
    last_frame: ?[]const u8 = null,
    frame_mutex: std.atomic.Mutex,

    const Self = @This();

    /// Initialize the stream server
    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: StreamConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .io = io,
            .config = config,
            .clients = .empty,
            .should_stop = std.atomic.Value(bool).init(false),
            .frame_mutex = .unlocked,
        };
        return self;
    }

    /// Start the server
    pub fn start(self: *Self) !void {
        // Bind to port
        const addr = std.Io.net.IpAddress.parse("0.0.0.0", self.config.port) catch
            return error.InvalidAddress;
        self.server = std.Io.net.IpAddress.listen(addr, self.io, .{
            .reuse_address = true,
        }) catch return error.BindFailed;

        // Start accept thread
        self.server_thread = try std.Thread.spawn(.{}, acceptLoop, .{self});

        std.debug.print("Stream server started at http://localhost:{d}/\n", .{self.config.port});
        if (self.config.interactive) {
            std.debug.print("Interactive mode enabled - viewers can interact\n", .{});
        }
    }

    fn acceptLoop(self: *Self) void {
        while (!self.should_stop.load(.acquire)) {
            if (self.server) |*srv| {
                const stream = srv.accept(self.io) catch continue;

                // Handle connection
                self.handleConnection(stream) catch |err| {
                    std.debug.print("Connection error: {}\n", .{err});
                };
            }
        }
    }

    fn handleConnection(self: *Self, stream: std.Io.net.Stream) !void {
        // Read HTTP request
        var read_buf: [4096]u8 = undefined;
        var reader = stream.reader(self.io, &read_buf);
        const chunk = reader.interface.peekGreedy(1) catch {
            stream.close(self.io);
            return;
        };

        if (chunk.len == 0) {
            stream.close(self.io);
            return;
        }

        // Read up to first double newline
        var request_buf: [4096]u8 = undefined;
        var request_len: usize = 0;
        while (request_len < request_buf.len - 1) {
            const peek = reader.interface.peekGreedy(1) catch break;
            if (peek.len == 0) break;
            request_buf[request_len] = peek[0];
            reader.interface.toss(1);
            request_len += 1;
            if (request_len >= 4 and std.mem.eql(u8, request_buf[request_len - 4 .. request_len], "\r\n\r\n")) {
                break;
            }
        }

        const request = request_buf[0..request_len];

        // Parse request path
        if (std.mem.startsWith(u8, request, "GET /stream")) {
            // MJPEG stream
            try self.handleMjpegStream(stream);
        } else if (std.mem.startsWith(u8, request, "GET /ws")) {
            // WebSocket upgrade
            try self.handleWebSocket(stream, request);
        } else if (std.mem.startsWith(u8, request, "GET /")) {
            // Serve viewer HTML
            try self.serveViewerPage(stream);
        } else {
            // 404
            var write_buf: [256]u8 = undefined;
            var writer = stream.writer(self.io, &write_buf);
            const response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found";
            _ = writer.interface.write(response) catch {};
            writer.interface.flush() catch {};
            stream.close(self.io);
        }
    }

    fn handleMjpegStream(self: *Self, stream: std.Io.net.Stream) !void {
        // Send MJPEG headers
        const headers =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n" ++
            "Cache-Control: no-cache\r\n" ++
            "Connection: keep-alive\r\n" ++
            "\r\n";

        var write_buf: [1024]u8 = undefined;
        var writer = stream.writer(self.io, &write_buf);
        _ = writer.interface.write(headers) catch return error.WriteFailed;
        writer.interface.flush() catch return error.WriteFailed;

        // Add to client list
        while (!self.frame_mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        self.clients.append(self.allocator, StreamClient{
            .stream = stream,
            .mode = .mjpeg,
        }) catch {};

        // Send last frame if available
        if (self.last_frame) |frame| {
            self.sendMjpegFrameToStream(stream, frame) catch {};
        }
        self.frame_mutex.unlock();
    }

    fn handleWebSocket(self: *Self, stream: std.Io.net.Stream, request: []const u8) !void {
        // Find Sec-WebSocket-Key
        const key_prefix = "Sec-WebSocket-Key: ";
        const key_start_idx = std.mem.indexOf(u8, request, key_prefix) orelse return error.InvalidWebSocket;
        const key_end_idx = std.mem.indexOfPos(u8, request, key_start_idx + key_prefix.len, "\r\n") orelse return error.InvalidWebSocket;
        const key = request[key_start_idx + key_prefix.len .. key_end_idx];

        // Calculate accept key
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(key);
        hasher.update(magic);
        const hash = hasher.finalResult();
        var accept_buf: [28]u8 = undefined;
        const accept_key = std.base64.standard.Encoder.encode(&accept_buf, &hash);

        // Send upgrade response
        var response_buf: [512]u8 = undefined;
        const response = std.fmt.bufPrint(&response_buf,
            "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n" ++
            "\r\n"
        , .{accept_key}) catch return error.BufferTooSmall;

        var write_buf: [1024]u8 = undefined;
        var writer = stream.writer(self.io, &write_buf);
        _ = writer.interface.write(response) catch return error.WriteFailed;
        writer.interface.flush() catch return error.WriteFailed;

        // Add to client list
        while (!self.frame_mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        self.clients.append(self.allocator, StreamClient{
            .stream = stream,
            .mode = .websocket,
        }) catch {};
        self.frame_mutex.unlock();

        // Handle WebSocket messages in loop
        if (self.config.interactive) {
            self.handleWebSocketMessages(stream) catch {};
        }
    }

    fn handleWebSocketMessages(self: *Self, stream: std.Io.net.Stream) !void {
        var read_buf: [4096]u8 = undefined;
        var reader = stream.reader(self.io, &read_buf);

        while (!self.should_stop.load(.acquire)) {
            // Read frame header
            _ = reader.interface.peek(2) catch break;
            const header = reader.interface.peekGreedy(2) catch break;
            if (header.len < 2) break;

            const opcode = header[0] & 0x0F;
            const masked = (header[1] & 0x80) != 0;
            var payload_len: usize = header[1] & 0x7F;
            reader.interface.toss(2);

            // Handle extended payload length
            if (payload_len == 126) {
                _ = reader.interface.peek(2) catch break;
                const ext = reader.interface.peekGreedy(2) catch break;
                if (ext.len < 2) break;
                payload_len = std.mem.readInt(u16, ext[0..2], .big);
                reader.interface.toss(2);
            } else if (payload_len == 127) {
                _ = reader.interface.peek(8) catch break;
                const ext = reader.interface.peekGreedy(8) catch break;
                if (ext.len < 8) break;
                payload_len = @intCast(std.mem.readInt(u64, ext[0..8], .big));
                reader.interface.toss(8);
            }

            // Read mask if present
            var mask: [4]u8 = undefined;
            if (masked) {
                _ = reader.interface.peek(4) catch break;
                const mask_data = reader.interface.peekGreedy(4) catch break;
                if (mask_data.len < 4) break;
                @memcpy(&mask, mask_data[0..4]);
                reader.interface.toss(4);
            }

            // Read payload
            if (payload_len > 65536) break; // Limit payload size
            const payload = self.allocator.alloc(u8, payload_len) catch break;
            defer self.allocator.free(payload);

            var total_read: usize = 0;
            while (total_read < payload_len) {
                _ = reader.interface.peek(1) catch break;
                const chunk = reader.interface.peekGreedy(payload_len - total_read) catch break;
                if (chunk.len == 0) break;
                @memcpy(payload[total_read..][0..chunk.len], chunk);
                reader.interface.toss(chunk.len);
                total_read += chunk.len;
            }

            // Unmask
            if (masked) {
                for (payload, 0..) |*b, i| {
                    b.* ^= mask[i % 4];
                }
            }

            // Handle message
            if (opcode == 0x1) { // Text frame
                self.handleInputMessage(payload) catch {};
            } else if (opcode == 0x8) { // Close
                break;
            }
        }
    }

    fn handleInputMessage(self: *Self, data: []const u8) !void {
        // Parse JSON input message
        // Expected: {"type": "click", "x": 100, "y": 200}
        if (self.input_callback == null) return;

        // Simple JSON parsing
        var input = ViewerInput{ .input_type = .click };

        if (std.mem.indexOf(u8, data, "\"click\"")) |_| {
            input.input_type = .click;
        } else if (std.mem.indexOf(u8, data, "\"mousemove\"")) |_| {
            input.input_type = .mousemove;
        } else if (std.mem.indexOf(u8, data, "\"keydown\"")) |_| {
            input.input_type = .keydown;
        }

        // Extract x coordinate
        if (std.mem.indexOf(u8, data, "\"x\":")) |pos| {
            const num_start = pos + 4;
            var num_end = num_start;
            while (num_end < data.len and (data[num_end] == ' ' or (data[num_end] >= '0' and data[num_end] <= '9') or data[num_end] == '-')) {
                num_end += 1;
            }
            const num_str = std.mem.trim(u8, data[num_start..num_end], " ");
            input.x = std.fmt.parseInt(i32, num_str, 10) catch null;
        }

        // Extract y coordinate
        if (std.mem.indexOf(u8, data, "\"y\":")) |pos| {
            const num_start = pos + 4;
            var num_end = num_start;
            while (num_end < data.len and (data[num_end] == ' ' or (data[num_end] >= '0' and data[num_end] <= '9') or data[num_end] == '-')) {
                num_end += 1;
            }
            const num_str = std.mem.trim(u8, data[num_start..num_end], " ");
            input.y = std.fmt.parseInt(i32, num_str, 10) catch null;
        }

        if (self.input_callback) |callback| {
            callback(input, self.input_ctx);
        }
    }

    fn serveViewerPage(self: *Self, stream: std.Io.net.Stream) !void {
        const html = getViewerHtml(self.config.interactive, self.config.port);
        var response_buf: [8192]u8 = undefined;
        const response = std.fmt.bufPrint(&response_buf,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/html\r\n" ++
            "Content-Length: {d}\r\n" ++
            "\r\n" ++
            "{s}"
        , .{ html.len, html }) catch return error.BufferTooSmall;

        var write_buf: [1024]u8 = undefined;
        var writer = stream.writer(self.io, &write_buf);
        _ = writer.interface.write(response) catch {};
        writer.interface.flush() catch {};
        stream.close(self.io);
    }

    fn sendMjpegFrameToStream(self: *Self, stream: std.Io.net.Stream, jpeg_data: []const u8) !void {
        var header_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf,
            "--frame\r\n" ++
            "Content-Type: image/jpeg\r\n" ++
            "Content-Length: {d}\r\n" ++
            "\r\n"
        , .{jpeg_data.len}) catch return error.BufferTooSmall;

        var write_buf: [1024]u8 = undefined;
        var writer = stream.writer(self.io, &write_buf);
        _ = writer.interface.write(header) catch return error.WriteFailed;
        writer.interface.flush() catch return error.WriteFailed;

        // Write data directly
        var offset: usize = 0;
        while (offset < jpeg_data.len) {
            const to_write = @min(jpeg_data.len - offset, 4096);
            _ = writer.interface.write(jpeg_data[offset..][0..to_write]) catch return error.WriteFailed;
            writer.interface.flush() catch return error.WriteFailed;
            offset += to_write;
        }

        _ = writer.interface.write("\r\n") catch return error.WriteFailed;
        writer.interface.flush() catch return error.WriteFailed;
    }

    /// Broadcast a frame to all connected clients
    pub fn broadcastFrame(self: *Self, frame: *const Frame) !void {
        while (!self.frame_mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.frame_mutex.unlock();

        // Store for new clients
        if (self.last_frame) |old| {
            self.allocator.free(old);
        }
        self.last_frame = try self.allocator.dupe(u8, frame.data);

        // Send to all MJPEG clients
        var i: usize = 0;
        while (i < self.clients.items.len) {
            const client = &self.clients.items[i];
            if (!client.active) {
                _ = self.clients.swapRemove(i);
                continue;
            }

            if (client.mode == .mjpeg) {
                self.sendMjpegFrameToStream(client.stream, frame.data) catch {
                    client.active = false;
                };
            } else if (client.mode == .websocket) {
                self.sendWebSocketFrame(client.stream, frame.data) catch {
                    client.active = false;
                };
            }
            i += 1;
        }
    }

    fn sendWebSocketFrame(self: *Self, stream: std.Io.net.Stream, data: []const u8) !void {
        // WebSocket binary frame
        var header: [10]u8 = undefined;
        var header_len: usize = 2;

        header[0] = 0x82; // Binary frame, FIN bit set

        if (data.len < 126) {
            header[1] = @intCast(data.len);
        } else if (data.len < 65536) {
            header[1] = 126;
            header[2] = @intCast((data.len >> 8) & 0xFF);
            header[3] = @intCast(data.len & 0xFF);
            header_len = 4;
        } else {
            header[1] = 127;
            std.mem.writeInt(u64, header[2..10], @intCast(data.len), .big);
            header_len = 10;
        }

        var write_buf: [1024]u8 = undefined;
        var writer = stream.writer(self.io, &write_buf);
        _ = writer.interface.write(header[0..header_len]) catch return error.WriteFailed;
        writer.interface.flush() catch return error.WriteFailed;

        // Write data in chunks
        var offset: usize = 0;
        while (offset < data.len) {
            const to_write = @min(data.len - offset, 4096);
            _ = writer.interface.write(data[offset..][0..to_write]) catch return error.WriteFailed;
            writer.interface.flush() catch return error.WriteFailed;
            offset += to_write;
        }
    }

    /// Set input callback for interactive mode
    pub fn setInputCallback(self: *Self, callback: InputCallback, ctx: ?*anyopaque) void {
        self.input_callback = callback;
        self.input_ctx = ctx;
    }

    /// Get the viewer URL
    pub fn getViewerUrl(self: *const Self) []const u8 {
        _ = self;
        return "http://localhost:8080/";
    }

    /// Get number of connected clients
    pub fn getClientCount(self: *Self) usize {
        while (!self.frame_mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.frame_mutex.unlock();
        return self.clients.items.len;
    }

    /// Stop the server
    pub fn stop(self: *Self) void {
        self.should_stop.store(true, .release);

        // Close server to unblock accept
        if (self.server) |*srv| {
            srv.deinit(self.io);
            self.server = null;
        }

        // Wait for server thread
        if (self.server_thread) |thread| {
            thread.join();
            self.server_thread = null;
        }

        // Close all clients
        while (!self.frame_mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        for (self.clients.items) |*client| {
            client.stream.close(self.io);
        }
        self.clients.clearRetainingCapacity();
        self.frame_mutex.unlock();
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.stop();

        if (self.last_frame) |frame| {
            self.allocator.free(frame);
        }

        self.clients.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

/// Get embedded viewer HTML
fn getViewerHtml(interactive: bool, port: u16) []const u8 {
    _ = port;
    if (interactive) {
        return
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <title>zchrome Replay Stream (Interactive)</title>
            \\  <style>
            \\    body { margin: 0; background: #1a1a2e; display: flex; justify-content: center; align-items: center; min-height: 100vh; }
            \\    #container { position: relative; }
            \\    #stream { max-width: 100vw; max-height: 100vh; cursor: crosshair; }
            \\    #status { position: fixed; top: 10px; left: 10px; color: #0f0; font-family: monospace; background: rgba(0,0,0,0.7); padding: 5px 10px; border-radius: 4px; }
            \\  </style>
            \\</head>
            \\<body>
            \\  <div id="status">Interactive Mode - Click to interact</div>
            \\  <div id="container">
            \\    <img id="stream" src="/stream">
            \\  </div>
            \\  <script>
            \\    const ws = new WebSocket('ws://' + location.host + '/ws');
            \\    const stream = document.getElementById('stream');
            \\    const status = document.getElementById('status');
            \\    
            \\    ws.onopen = () => { status.textContent = 'Connected - Click to interact'; };
            \\    ws.onclose = () => { status.textContent = 'Disconnected'; };
            \\    
            \\    stream.addEventListener('click', (e) => {
            \\      const rect = stream.getBoundingClientRect();
            \\      const scaleX = stream.naturalWidth / rect.width;
            \\      const scaleY = stream.naturalHeight / rect.height;
            \\      const x = Math.round((e.clientX - rect.left) * scaleX);
            \\      const y = Math.round((e.clientY - rect.top) * scaleY);
            \\      ws.send(JSON.stringify({ type: 'click', x, y }));
            \\      status.textContent = 'Clicked at (' + x + ', ' + y + ')';
            \\    });
            \\    
            \\    document.addEventListener('keydown', (e) => {
            \\      ws.send(JSON.stringify({ type: 'keydown', key: e.key }));
            \\    });
            \\  </script>
            \\</body>
            \\</html>
        ;
    } else {
        return
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <title>zchrome Replay Stream</title>
            \\  <style>
            \\    body { margin: 0; background: #1a1a2e; display: flex; justify-content: center; align-items: center; min-height: 100vh; }
            \\    #stream { max-width: 100vw; max-height: 100vh; }
            \\    #status { position: fixed; top: 10px; left: 10px; color: #0f0; font-family: monospace; background: rgba(0,0,0,0.7); padding: 5px 10px; border-radius: 4px; }
            \\  </style>
            \\</head>
            \\<body>
            \\  <div id="status">Streaming...</div>
            \\  <img id="stream" src="/stream">
            \\</body>
            \\</html>
        ;
    }
}
