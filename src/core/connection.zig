const std = @import("std");
const protocol = @import("protocol.zig");
const WebSocket = @import("../transport/websocket.zig").WebSocket;
const WebSocketError = @import("../transport/websocket.zig").WebSocketError;
const Session = @import("session.zig").Session;

const json_util = @import("../util/json.zig");

/// CDP Connection - synchronous version for Zig 0.16
/// Handles WebSocket communication with Chrome DevTools Protocol
pub const Connection = struct {
    websocket: WebSocket,
    allocator: std.mem.Allocator,
    id_allocator: protocol.IdAllocator,
    last_error: ?protocol.ErrorPayload,
    receive_timeout_ms: u32,
    verbose: bool,

    const Self = @This();

    pub const Options = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        receive_timeout_ms: u32 = 30_000,
        verbose: bool = false,
    };

    /// Open a connection to a WebSocket URL
    pub fn open(ws_url: []const u8, opts: Options) !*Self {
        // Parse ws:// URL to extract host, port, path
        const host_start = if (std.mem.startsWith(u8, ws_url, "wss://"))
            @as(usize, 6)
        else if (std.mem.startsWith(u8, ws_url, "ws://"))
            @as(usize, 5)
        else
            return error.InvalidUrl;

        const rest = ws_url[host_start..];

        // Find path separator
        const path_start = std.mem.indexOf(u8, rest, "/") orelse rest.len;
        const host_port = rest[0..path_start];
        const path = if (path_start < rest.len) rest[path_start..] else "/";

        // Parse host and port
        var host: []const u8 = undefined;
        var port: u16 = if (std.mem.startsWith(u8, ws_url, "wss://")) 443 else 80;

        if (std.mem.indexOf(u8, host_port, ":")) |colon| {
            host = host_port[0..colon];
            port = std.fmt.parseInt(u16, host_port[colon + 1 ..], 10) catch return error.InvalidUrl;
        } else {
            host = host_port;
        }

        // Connect
        const websocket = WebSocket.connect(.{
            .host = host,
            .port = port,
            .path = path,
            .tls = std.mem.startsWith(u8, ws_url, "wss://"),
            .allocator = opts.allocator,
            .io = opts.io,
        }) catch return error.ConnectionFailed;

        const self = try opts.allocator.create(Self);
        self.* = .{
            .websocket = websocket,
            .allocator = opts.allocator,
            .id_allocator = protocol.IdAllocator.init(),
            .last_error = null,
            .receive_timeout_ms = opts.receive_timeout_ms,
            .verbose = opts.verbose,
        };

        return self;
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        self.websocket.close();
    }

    /// Send a CDP command and wait for response (synchronous)
    pub fn sendCommand(
        self: *Self,
        method: []const u8,
        params: anytype,
        session_id: ?[]const u8,
    ) !std.json.Value {
        const id = self.id_allocator.next();

        // Serialize and send
        const json_str = try protocol.serializeCommand(
            self.allocator,
            id,
            method,
            params,
            session_id,
        );
        defer self.allocator.free(json_str);

        if (self.verbose) {
            std.debug.print("-> {s}\n", .{json_str});
        }

        try self.websocket.sendText(json_str);

        // Read response synchronously
        // Keep reading until we get a response with our id
        var attempts: u32 = 0;
        const max_attempts: u32 = 1000;

        while (attempts < max_attempts) : (attempts += 1) {
            var msg = self.websocket.receiveMessage() catch |err| {
                if (self.verbose) {
                    std.debug.print("Receive error: {}\n", .{err});
                }
                return error.ConnectionClosed;
            };
            defer msg.deinit(self.allocator);

            if (self.verbose) {
                std.debug.print("<- {s}\n", .{msg.data});
            }

            // Parse JSON
            const parsed = std.json.parseFromSlice(
                std.json.Value,
                self.allocator,
                msg.data,
                .{},
            ) catch continue;
            defer parsed.deinit();

            // Check if this is our response
            if (parsed.value.object.get("id")) |id_val| {
                if (id_val == .integer and id_val.integer == id) {
                    // Check for error
                    if (parsed.value.object.get("error")) |err_val| {
                        if (err_val.object.get("code")) |code_val| {
                            const code: i32 = @intCast(code_val.integer);
                            return mapCdpError(code);
                        }
                        return error.ProtocolError;
                    }

                    // Return the result
                    if (parsed.value.object.get("result")) |result| {
                        // Clone the result since parsed will be deallocated
                        return try cloneJsonValue(self.allocator, result);
                    }

                    // Empty result is valid for some commands
                    return emptyObjectValue(self.allocator);
                }
            }

            // Not our response, might be an event - continue reading
        }

        return error.Timeout;
    }

    /// Get last error
    pub fn getLastError(self: *Self) ?protocol.ErrorPayload {
        return self.last_error;
    }

    /// Create a session attached to a target
    pub fn createSession(self: *Self, target_id: []const u8) !*Session {
        const result = try self.sendCommand("Target.attachToTarget", .{
            .targetId = target_id,
            .flatten = true,
        }, null);

        const session_id = try json_util.getString(result, "sessionId");
        // Dupe the session_id since result memory may be invalidated
        const owned_id = try self.allocator.dupe(u8, session_id);
        return Session.init(owned_id, self, self.allocator);
    }

    /// Destroy a session
    pub fn destroySession(self: *Self, session_id: []const u8) !void {
        _ = try self.sendCommand("Target.detachFromTarget", .{
            .sessionId = session_id,
        }, null);
    }
};

/// Clone a JSON value (deep copy)
fn cloneJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    switch (value) {
        .null => return .null,
        .bool => |b| return .{ .bool = b },
        .integer => |i| return .{ .integer = i },
        .float => |f| return .{ .float = f },
        .number_string => |s| return .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| return .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            var new_arr = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try new_arr.append(try cloneJsonValue(allocator, item));
            }
            return .{ .array = new_arr };
        },
        .object => |obj| {
            var new_obj = std.json.ObjectMap.init(allocator);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const val = try cloneJsonValue(allocator, entry.value_ptr.*);
                try new_obj.put(key, val);
            }
            return .{ .object = new_obj };
        },
    }
}

/// Create an empty JSON object
fn emptyObjectValue(allocator: std.mem.Allocator) std.json.Value {
    return .{ .object = std.json.ObjectMap.init(allocator) };
}

/// Map CDP error code to Zig error
fn mapCdpError(code: i32) error{
    InvalidParams,
    MethodNotFound,
    InternalError,
    InvalidRequest,
    ServerError,
    ProtocolError,
} {
    return switch (code) {
        -32600 => error.InvalidRequest,
        -32601 => error.MethodNotFound,
        -32602 => error.InvalidParams,
        -32603 => error.InternalError,
        else => if (code >= -32099 and code <= -32000)
            error.ServerError
        else
            error.ProtocolError,
    };
}


