const std = @import("std");
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

    /// Send a command through this session
    pub fn sendCommand(
        self: *Self,
        method: []const u8,
        params: anytype,
    ) !std.json.Value {
        return self.connection.sendCommand(method, params, self.id);
    }

    /// Detach from the target
    pub fn detach(self: *Self) !void {
        _ = try self.connection.sendCommand("Target.detachFromTarget", .{
            .sessionId = self.id,
        }, null);
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
