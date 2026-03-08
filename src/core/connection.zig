const std = @import("std");
const json = @import("json");
const protocol = @import("protocol.zig");
const wss = @import("wss");
const WebSocket = wss.Client;
const WebSocketError = wss.Error;
const Session = @import("session.zig").Session;

/// CDP Connection - synchronous version for Zig 0.16
/// Handles WebSocket communication with Chrome DevTools Protocol
pub const Connection = struct {
    websocket: WebSocket,
    allocator: std.mem.Allocator,
    id_allocator: protocol.IdAllocator,
    last_error: ?protocol.ErrorPayload,
    receive_timeout_ms: u32,
    verbose: bool,
    /// Buffer for events received during command execution (to avoid losing them)
    event_buffer: std.ArrayList(BufferedEvent),

    const Self = @This();

    const BufferedEvent = struct {
        method: []const u8,
        params: json.Value,
        session_id: ?[]const u8,

        fn deinit(self: *BufferedEvent, alloc: std.mem.Allocator) void {
            alloc.free(self.method);
            if (self.session_id) |sid| alloc.free(sid);
            self.params.deinit(alloc);
        }
    };

    fn bufferParsedEvent(self: *Self, parsed: json.Value) void {
        if (parsed.get("method")) |method_val| {
            if (method_val == .string) {
                const method_copy = self.allocator.dupe(u8, method_val.string) catch return;
                errdefer self.allocator.free(method_copy);

                var params_clone = if (parsed.get("params")) |p|
                    p.clone(self.allocator) catch {
                        self.allocator.free(method_copy);
                        return;
                    }
                else
                    json.emptyObject();
                errdefer params_clone.deinit(self.allocator);

                const session_id_copy: ?[]const u8 = if (parsed.get("sessionId")) |sid|
                    (if (sid == .string) self.allocator.dupe(u8, sid.string) catch null else null)
                else
                    null;

                self.event_buffer.append(self.allocator, .{
                    .method = method_copy,
                    .params = params_clone,
                    .session_id = session_id_copy,
                }) catch {
                    self.allocator.free(method_copy);
                    params_clone.deinit(self.allocator);
                    if (session_id_copy) |s| self.allocator.free(s);
                };
            }
        }
    }

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
            .event_buffer = std.ArrayList(BufferedEvent).empty,
        };

        return self;
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        // Clean up buffered events
        for (self.event_buffer.items) |*evt| {
            evt.deinit(self.allocator);
        }
        self.event_buffer.deinit(self.allocator);
        self.websocket.close();
    }

    /// Send a CDP command and wait for response (synchronous)
    /// Returns a parsed json.Value. Caller must call value.deinit(allocator) when done.
    pub fn sendCommand(
        self: *Self,
        method: []const u8,
        params: anytype,
        session_id: ?[]const u8,
    ) !json.Value {
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
            var parsed = json.parse(self.allocator, msg.data, .{}) catch continue;
            errdefer parsed.deinit(self.allocator);

            if (parsed != .object) continue;

            // Check if this is our response
            if (parsed.get("id")) |id_val| {
                const resp_id: i64 = switch (id_val) {
                    .integer => |i| i,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => continue,
                };
                if (resp_id == id) {
                    // Check for error
                    if (parsed.get("error")) |err_val| {
                        if (err_val.get("code")) |code_val| {
                            const code: i32 = @intCast(switch (code_val) {
                                .integer => |i| i,
                                else => return error.ProtocolError,
                            });
                            parsed.deinit(self.allocator);
                            return mapCdpError(code);
                        }
                        parsed.deinit(self.allocator);
                        return error.ProtocolError;
                    }

                    // Return just the result object (not the full response)
                    if (parsed.object.get("result")) |result_val| {
                        // Clone the result value so we can free the full response
                        const result_clone = result_val.clone(self.allocator) catch {
                            parsed.deinit(self.allocator);
                            return error.OutOfMemory;
                        };
                        parsed.deinit(self.allocator);
                        return result_clone;
                    }

                    // Empty result is valid for some commands
                    // Return empty object
                    parsed.deinit(self.allocator);
                    return json.emptyObject();
                }
            }

            // Not our response, buffer events for later retrieval
            self.bufferParsedEvent(parsed);
            parsed.deinit(self.allocator);
        }

        return error.Timeout;
    }

    /// Get last error
    pub fn getLastError(self: *Self) ?protocol.ErrorPayload {
        return self.last_error;
    }

    /// Send a command and discard the result (automatically frees memory).
    /// Use this for commands where you don't need the response data.
    pub fn sendCommandIgnoreResult(
        self: *Self,
        method: []const u8,
        params: anytype,
        session_id: ?[]const u8,
    ) !void {
        var result = try self.sendCommand(method, params, session_id);
        result.deinit(self.allocator);
    }

    /// Wait for a specific CDP event by method name.
    /// Returns the event params as json.Value. Caller must call value.deinit(allocator) when done.
    /// This will discard any command responses received while waiting.
    pub fn waitForEvent(
        self: *Self,
        event_method: []const u8,
        expected_session_id: ?[]const u8,
        timeout_ms: u32,
    ) !json.Value {
        // First, check the event buffer for already-received events
        var idx: usize = 0;
        while (idx < self.event_buffer.items.len) {
            const evt = self.event_buffer.items[idx];
            const method_matches = std.mem.eql(u8, evt.method, event_method);
            const session_matches = if (expected_session_id) |sid|
                (evt.session_id != null and std.mem.eql(u8, evt.session_id.?, sid))
            else
                true;

            if (method_matches and session_matches) {
                // Found the event in buffer, remove and return it
                var removed_evt = self.event_buffer.orderedRemove(idx);
                self.allocator.free(removed_evt.method);
                if (removed_evt.session_id) |sid| self.allocator.free(sid);
                return removed_evt.params; // Caller owns params
            }
            idx += 1;
        }

        // Not in buffer, wait for it from websocket
        const max_attempts: u32 = if (timeout_ms == 0) 1000 else timeout_ms / 10;
        var attempts: u32 = 0;

        while (attempts < max_attempts) : (attempts += 1) {
            var msg = self.websocket.receiveMessage() catch |err| {
                if (self.verbose) {
                    std.debug.print("Receive error: {}\\n", .{err});
                }
                return error.ConnectionClosed;
            };
            defer msg.deinit(self.allocator);

            if (self.verbose) {
                std.debug.print("<- {s}\\n", .{msg.data});
            }

            // Parse JSON
            var parsed = json.parse(self.allocator, msg.data, .{}) catch continue;
            errdefer parsed.deinit(self.allocator);

            if (parsed != .object) {
                parsed.deinit(self.allocator);
                continue;
            }

            // Check if this is the event we're waiting for
            if (parsed.get("method")) |method_val| {
                if (method_val == .string) {
                    const parsed_session_id: ?[]const u8 = if (parsed.get("sessionId")) |sid|
                        (if (sid == .string) sid.string else null)
                    else
                        null;

                    const method_matches = std.mem.eql(u8, method_val.string, event_method);
                    const session_matches = if (expected_session_id) |sid|
                        (parsed_session_id != null and std.mem.eql(u8, parsed_session_id.?, sid))
                    else
                        true;

                    if (method_matches and session_matches) {
                        // Found the event, return the params
                        if (parsed.object.get("params")) |params_val| {
                            const result = params_val.clone(self.allocator) catch {
                                parsed.deinit(self.allocator);
                                return error.OutOfMemory;
                            };
                            parsed.deinit(self.allocator);
                            return result;
                        }
                        // Event with no params - return empty object
                        parsed.deinit(self.allocator);
                        return json.emptyObject();
                    } else {
                        // Not the event we want, buffer it for later
                        self.bufferParsedEvent(parsed);
                    }
                }
            }

            parsed.deinit(self.allocator);
        }

        return error.Timeout;
    }

    /// Create a session attached to a target
    pub fn createSession(self: *Self, target_id: []const u8) !*Session {
        var result = try self.sendCommand("Target.attachToTarget", .{
            .targetId = target_id,
            .flatten = true,
        }, null);
        defer result.deinit(self.allocator);

        // Extract sessionId from result
        const session_id = if (result.get("result")) |res|
            res.getString("sessionId") catch return error.InvalidResponse
        else
            result.getString("sessionId") catch return error.InvalidResponse;

        // Dupe the session_id since result memory will be freed
        const owned_id = try self.allocator.dupe(u8, session_id);
        return Session.init(owned_id, self, self.allocator);
    }

    /// Destroy a session
    pub fn destroySession(self: *Self, session_id: []const u8) !void {
        var result = try self.sendCommand("Target.detachFromTarget", .{
            .sessionId = session_id,
        }, null);
        result.deinit(self.allocator);
    }
};

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
