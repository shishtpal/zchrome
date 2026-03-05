const std = @import("std");
const json = @import("json");
const Connection = @import("connection.zig").Connection;
const protocol = @import("protocol.zig");

/// A session attached to a specific target (browser tab, worker, etc.)
/// Commands sent through a session are multiplexed via sessionId
pub const Session = struct {
    id: []const u8,
    connection: *Connection,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize a session
    pub fn init(
        id: []const u8,
        connection: *Connection,
        allocator: std.mem.Allocator,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .id = try allocator.dupe(u8, id),
            .connection = connection,
            .allocator = allocator,
        };
        return self;
    }

    /// Send a command through this session.
    /// Returns a json.Value. Caller must call value.deinit(allocator) when done.
    pub fn sendCommand(
        self: *Self,
        method: []const u8,
        params: anytype,
    ) !json.Value {
        const sid = if (self.id.len > 0) self.id else null;
        return self.connection.sendCommand(method, params, sid);
    }

    /// Send a command and discard the result (automatically frees memory).
    /// Use this for commands where you don't need the response data.
    pub fn sendCommandIgnoreResult(
        self: *Self,
        method: []const u8,
        params: anytype,
    ) !void {
        const sid = if (self.id.len > 0) self.id else null;
        try self.connection.sendCommandIgnoreResult(method, params, sid);
    }

    /// Detach from the target
    pub fn detach(self: *Self) !void {
        var result = try self.connection.sendCommand("Target.detachFromTarget", .{
            .sessionId = self.id,
        }, null);
        result.deinit(self.allocator);
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.id);
        self.allocator.destroy(self);
    }

    /// Get the session ID
    pub fn getId(self: *const Self) []const u8 {
        return self.id;
    }
};
