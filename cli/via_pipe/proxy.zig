//! CDP Proxy Server for pipe mode.
//!
//! Provides a WebSocket server that forwards CDP commands to Chrome via pipe.
//! This allows other zchrome instances to send commands to a pipe-mode Chrome.
//!
//! CDP Protocol notes:
//! - Commands have an "id" field
//! - Responses have a matching "id" field
//! - Events have a "method" field but NO "id" field
//! The proxy must forward events AND match responses by ID.

const std = @import("std");
const wss = @import("wss");
const json = @import("json");
const launcher = @import("launcher.zig");
const globals = @import("../globals.zig");

const ChromePipe = launcher.ChromePipe;

/// CDP Proxy Server that bridges WebSocket clients to Chrome pipe.
pub const CdpProxyServer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    chrome_pipe: *ChromePipe,
    port: u16,
    ws_server: wss.Server,
    running: bool = false,

    const Self = @This();

    /// Initialize the proxy server and bind to port.
    /// The actual bound port is available via self.port after init.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        chrome_pipe: *ChromePipe,
        port: u16,
    ) !*Self {
        // Bind server immediately so actual port is known
        const ws_server = wss.Server.init(allocator, io, port) catch |err| {
            std.debug.print("Failed to start WebSocket server on port {}: {}\n", .{ port, err });
            return error.ServerStartFailed;
        };

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .chrome_pipe = chrome_pipe,
            .port = ws_server.port, // actual bound port
            .ws_server = ws_server,
        };
        return self;
    }

    /// Start the proxy server and run until client disconnects or error.
    /// This is a blocking call - it handles one client at a time.
    pub fn run(self: *Self) !void {
        self.running = true;

        std.debug.print("CDP proxy listening on ws://127.0.0.1:{d}/\n", .{self.port});
        std.debug.print("Waiting for client connection...\n", .{});

        // Accept client connections in a loop (reconnection support)
        while (self.running) {
            // Accept one client connection
            var conn = self.ws_server.accept() catch |err| {
                if (globals.verbose) {
                    std.debug.print("WebSocket accept error: {}\n", .{err});
                }
                // Continue waiting for next connection
                continue;
            };
            defer conn.close();

            std.debug.print("Client connected. Forwarding CDP commands...\n", .{});
            self.handleClient(&conn);
            std.debug.print("Client disconnected.\n", .{});
        }
    }

    fn handleClient(self: *Self, conn: *wss.Connection) void {
        // Message loop: read WebSocket frame -> forward to pipe -> send responses
        while (self.running) {
            const msg = conn.readFrame() catch |err| {
                if (err == wss.Error.ConnectionClosed) {
                    break;
                }
                if (globals.verbose) {
                    std.debug.print("WebSocket read error: {}\n", .{err});
                }
                break;
            };
            defer self.allocator.free(msg.data);

            switch (msg.opcode) {
                .text => {
                    // Extract command ID from the request
                    const cmd_id = extractId(self.allocator, msg.data);

                    // Send command to Chrome via pipe
                    self.chrome_pipe.sendCommandOnly(msg.data) catch |err| {
                        std.debug.print("Pipe send error: {}\n", .{err});
                        // Include command ID in error response so client can match it
                        if (cmd_id) |id| {
                            const error_json = std.fmt.allocPrint(
                                self.allocator,
                                "{{\"id\":{d},\"error\":{{\"code\":-32603,\"message\":\"Pipe communication error\"}}}}",
                                .{id},
                            ) catch {
                                conn.sendText("{\"error\":{\"code\":-32603,\"message\":\"Pipe communication error\"}}") catch {};
                                continue;
                            };
                            defer self.allocator.free(error_json);
                            conn.sendText(error_json) catch {};
                        } else {
                            conn.sendText("{\"error\":{\"code\":-32603,\"message\":\"Pipe communication error\"}}") catch {};
                        }
                        continue;
                    };

                    // Read responses from Chrome until we get one with matching ID
                    // Forward all events to client along the way
                    self.readAndForwardResponses(conn, cmd_id) catch |err| {
                        if (globals.verbose) {
                            std.debug.print("Response forwarding error: {}\n", .{err});
                        }
                        break;
                    };
                },
                .ping => {
                    conn.sendPong(msg.data) catch {};
                },
                .close => {
                    break;
                },
                else => {
                    // Ignore other frame types
                },
            }
        }
    }

    /// Read messages from Chrome pipe and forward to WebSocket client.
    /// Keeps reading until a response with matching ID is found.
    /// Has a safety limit to prevent infinite loops if Chrome becomes unresponsive.
    fn readAndForwardResponses(self: *Self, conn: *wss.Connection, expected_id: ?i64) !void {
        const max_iterations: u32 = 1000; // Safety limit
        var iterations: u32 = 0;

        while (iterations < max_iterations) : (iterations += 1) {
            // Read one message from Chrome
            const response = self.chrome_pipe.readOneMessage() catch |err| {
                return err;
            };
            defer self.allocator.free(response);

            if (globals.verbose) {
                std.debug.print("[proxy] <- {s}\n", .{response});
            }

            // Forward to WebSocket client
            conn.sendText(response) catch |err| {
                return err;
            };

            // Check if this is the response we're waiting for
            const resp_id = extractId(self.allocator, response);
            if (expected_id) |eid| {
                if (resp_id) |rid| {
                    if (rid == eid) {
                        // Found matching response, command is complete
                        return;
                    }
                }
            } else {
                // No expected ID (shouldn't happen), just return after first message
                return;
            }

            // This was an event or different response, keep reading
        }

        // Safety limit reached - Chrome may be stuck or flooding events
        if (globals.verbose) {
            std.debug.print("Warning: response iteration limit reached\n", .{});
        }
        return error.ResponseTimeout;
    }

    /// Stop the proxy server.
    pub fn stop(self: *Self) void {
        self.running = false;
    }

    /// Clean up resources.
    pub fn deinit(self: *Self) void {
        self.ws_server.close();
        self.allocator.destroy(self);
    }
};

/// Extract "id" field from JSON message, returns null if not found or not a number.
fn extractId(allocator: std.mem.Allocator, json_str: []const u8) ?i64 {
    var parsed = json.parse(allocator, json_str, .{}) catch return null;
    defer parsed.deinit(allocator);

    if (parsed.get("id")) |id_val| {
        if (id_val == .integer) {
            return id_val.integer;
        }
    }
    return null;
}
