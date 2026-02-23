//! Recording server for macro capture via WebSocket.
//!
//! Uses a background thread to handle WebSocket connections while
//! the main thread waits for user input.

const std = @import("std");
const cdp = @import("cdp");
const macro_mod = @import("macro.zig");

pub const DEFAULT_PORT: u16 = 4040;

/// Thread-safe event storage
const EventStorage = struct {
    events: std.ArrayList(macro_mod.MacroEvent),
    mutex: std.atomic.Mutex,
    allocator: std.mem.Allocator,
    start_time: i64,

    fn init(allocator: std.mem.Allocator, io: std.Io) EventStorage {
        const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
        const now_ms: i64 = @intCast(@divTrunc(now_ns, std.time.ns_per_ms));
        return .{
            .events = .empty,
            .mutex = .unlocked,
            .allocator = allocator,
            .start_time = now_ms,
        };
    }

    fn addEvent(self: *EventStorage, event: macro_mod.MacroEvent) void {
        // Spin until we get the lock
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        self.events.append(self.allocator, event) catch {};
    }

    fn getEvents(self: *EventStorage) []macro_mod.MacroEvent {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        return self.events.items;
    }

    fn deinit(self: *EventStorage) void {
        for (self.events.items) |*e| {
            e.deinit(self.allocator);
        }
        self.events.deinit(self.allocator);
    }
};

/// Recording server state
pub const RecordServer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    storage: *EventStorage,
    port: u16,
    should_stop: std.atomic.Value(bool),
    thread: ?std.Thread,

    const Self = @This();

    /// Start the recording server in a background thread
    pub fn init(allocator: std.mem.Allocator, io: std.Io, port: u16) !*Self {
        const storage = try allocator.create(EventStorage);
        storage.* = EventStorage.init(allocator, io);

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .storage = storage,
            .port = port,
            .should_stop = std.atomic.Value(bool).init(false),
            .thread = null,
        };

        // Start background thread
        self.thread = std.Thread.spawn(.{}, serverThread, .{ self, io }) catch |err| {
            std.debug.print("Failed to spawn server thread: {}\n", .{err});
            allocator.destroy(storage);
            allocator.destroy(self);
            return err;
        };

        return self;
    }

    fn serverThread(self: *Self, io: std.Io) void {
        // Start WebSocket server
        var server = cdp.WsServer.init(self.allocator, io, self.port) catch |err| {
            std.debug.print("Failed to start WebSocket server: {}\n", .{err});
            return;
        };
        defer server.close();

        // Accept and process connections until stopped
        while (!self.should_stop.load(.acquire)) {
            // Accept connection (blocking)
            var client = server.accept() catch {
                continue;
            };
            std.debug.print("  (browser connected)\n", .{});

            // Process messages until disconnect or stop
            while (!self.should_stop.load(.acquire)) {
                const frame = client.readFrame() catch |err| {
                    if (err == cdp.WsServerError.ConnectionClosed) {
                        std.debug.print("  (browser disconnected)\n", .{});
                        break;
                    }
                    continue;
                };
                defer self.allocator.free(frame.data);

                // Handle close frame
                if (frame.opcode == 0x8) break;

                // Handle text frame (event data)
                if (frame.opcode == 0x1) {
                    self.parseAndStoreEvent(frame.data);
                }
            }

            client.close();
        }
    }

    fn parseAndStoreEvent(self: *Self, data: []const u8) void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch return;
        defer parsed.deinit();

        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        var event = macro_mod.MacroEvent{
            .event_type = .mouseMove,
            .timestamp = 0,
        };

        // Parse event type
        if (obj.get("type")) |t| {
            if (t == .string) {
                if (std.mem.eql(u8, t.string, "mousemove")) {
                    event.event_type = .mouseMove;
                } else if (std.mem.eql(u8, t.string, "mousedown")) {
                    event.event_type = .mouseDown;
                } else if (std.mem.eql(u8, t.string, "mouseup")) {
                    event.event_type = .mouseUp;
                } else if (std.mem.eql(u8, t.string, "wheel")) {
                    event.event_type = .mouseWheel;
                } else if (std.mem.eql(u8, t.string, "keydown")) {
                    event.event_type = .keyDown;
                } else if (std.mem.eql(u8, t.string, "keyup")) {
                    event.event_type = .keyUp;
                } else return;
            }
        }

        // Use current timestamp relative to start
        const now_ns = std.Io.Timestamp.now(self.io, .real).nanoseconds;
        const now_ms: i64 = @intCast(@divTrunc(now_ns, std.time.ns_per_ms));
        event.timestamp = now_ms - self.storage.start_time;

        // Parse coordinates
        if (obj.get("x")) |x| {
            if (x == .float) event.x = x.float;
            if (x == .integer) event.x = @floatFromInt(x.integer);
        }
        if (obj.get("y")) |y| {
            if (y == .float) event.y = y.float;
            if (y == .integer) event.y = @floatFromInt(y.integer);
        }

        // Parse mouse button
        if (obj.get("button")) |b| {
            if (b == .integer) event.button = macro_mod.MouseButton.fromInt(b.integer);
        }

        // Parse wheel deltas
        if (obj.get("deltaX")) |dx| {
            if (dx == .float) event.delta_x = dx.float;
            if (dx == .integer) event.delta_x = @floatFromInt(dx.integer);
        }
        if (obj.get("deltaY")) |dy| {
            if (dy == .float) event.delta_y = dy.float;
            if (dy == .integer) event.delta_y = @floatFromInt(dy.integer);
        }

        // Parse key properties
        if (obj.get("key")) |k| {
            if (k == .string) event.key = self.allocator.dupe(u8, k.string) catch null;
        }
        if (obj.get("code")) |c| {
            if (c == .string) event.code = self.allocator.dupe(u8, c.string) catch null;
        }
        if (obj.get("modifiers")) |m| {
            if (m == .integer) event.modifiers = @intCast(m.integer);
        }

        self.storage.addEvent(event);
    }

    /// Stop recording and get events
    pub fn stop(self: *Self) []macro_mod.MacroEvent {
        self.should_stop.store(true, .release);

        // Connect to self to unblock accept
        const addr = std.Io.net.IpAddress.parse("127.0.0.1", self.port) catch return self.storage.getEvents();
        const conn = std.Io.net.IpAddress.connect(addr, self.io, .{
            .mode = .stream,
            .protocol = .tcp,
        }) catch return self.storage.getEvents();
        conn.close(self.io);

        // Wait for thread to finish
        if (self.thread) |t| {
            t.join();
        }

        return self.storage.getEvents();
    }

    /// Clean up
    pub fn deinit(self: *Self) void {
        self.storage.deinit();
        self.allocator.destroy(self.storage);
        self.allocator.destroy(self);
    }
};

/// JavaScript to inject that connects to WebSocket and streams events
pub fn getRecordingJs(allocator: std.mem.Allocator, port: u16) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\(function() {{
        \\  if (window.__zchrome_ws) return;
        \\  var ws = new WebSocket('ws://127.0.0.1:{d}/');
        \\  window.__zchrome_ws = ws;
        \\  ws.onopen = function() {{
        \\    console.log('[zchrome] Recording connected');
        \\  }};
        \\  ws.onclose = function() {{
        \\    window.__zchrome_ws = null;
        \\    console.log('[zchrome] Recording disconnected');
        \\  }};
        \\  function send(e) {{
        \\    if (!ws || ws.readyState !== 1) return;
        \\    var ev = {{ type: e.type }};
        \\    if (e.clientX !== undefined) {{ ev.x = e.clientX; ev.y = e.clientY; }}
        \\    if (e.button !== undefined) ev.button = e.button;
        \\    if (e.deltaX !== undefined) {{ ev.deltaX = e.deltaX; ev.deltaY = e.deltaY; }}
        \\    if (e.key !== undefined) {{ ev.key = e.key; ev.code = e.code; }}
        \\    ev.modifiers = (e.altKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.metaKey ? 4 : 0) | (e.shiftKey ? 8 : 0);
        \\    ws.send(JSON.stringify(ev));
        \\  }}
        \\  ['mousedown', 'mouseup', 'mousemove', 'wheel', 'keydown', 'keyup'].forEach(function(t) {{
        \\    document.addEventListener(t, send, true);
        \\  }});
        \\}})();
    , .{port});
}
