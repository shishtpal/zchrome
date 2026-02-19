const std = @import("std");
const Connection = @import("../core/connection.zig").Connection;
const json_util = @import("../util/json.zig");

/// Browser domain client
pub const BrowserDomain = struct {
    connection: *Connection,

    const Self = @This();

    pub fn init(connection: *Connection) Self {
        return .{ .connection = connection };
    }

    /// Get browser version
    pub fn getVersion(self: *Self, allocator: std.mem.Allocator) !BrowserVersion {
        const result = try self.connection.sendCommand("Browser.getVersion", .{});

        return .{
            .protocol_version = try allocator.dupe(u8, try json_util.getString(result, "protocolVersion")),
            .product = try allocator.dupe(u8, try json_util.getString(result, "product")),
            .revision = try allocator.dupe(u8, try json_util.getString(result, "revision")),
            .user_agent = try allocator.dupe(u8, try json_util.getString(result, "userAgent")),
            .js_version = try allocator.dupe(u8, try json_util.getString(result, "jsVersion")),
        };
    }

    /// Close browser
    pub fn close(self: *Self) !void {
        _ = try self.connection.sendCommand("Browser.close", .{});
    }

    /// Get window for target
    pub fn getWindowForTarget(self: *Self, allocator: std.mem.Allocator, target_id: ?[]const u8) !WindowInfo {
        const result = try self.connection.sendCommand("Browser.getWindowForTarget", .{
            .target_id = target_id,
        });

        return .{
            .window_id = try json_util.getInt(result, "windowId"),
            .bounds = try parseBounds(allocator, result.object.get("bounds") orelse return error.MissingField),
        };
    }

    /// Set window bounds
    pub fn setWindowBounds(self: *Self, window_id: i64, bounds: Bounds) !void {
        _ = try self.connection.sendCommand("Browser.setWindowBounds", .{
            .window_id = window_id,
            .bounds = bounds,
        });
    }

    /// Get window bounds
    pub fn getWindowBounds(self: *Self, allocator: std.mem.Allocator, window_id: i64) !Bounds {
        const result = try self.connection.sendCommand("Browser.getWindowBounds", .{
            .window_id = window_id,
        });

        return try parseBounds(allocator, result.object.get("bounds") orelse return error.MissingField);
    }
};

/// Browser version information
pub const BrowserVersion = struct {
    protocol_version: []const u8,
    product: []const u8,
    revision: []const u8,
    user_agent: []const u8,
    js_version: []const u8,

    pub fn deinit(self: *BrowserVersion, allocator: std.mem.Allocator) void {
        allocator.free(self.protocol_version);
        allocator.free(self.product);
        allocator.free(self.revision);
        allocator.free(self.user_agent);
        allocator.free(self.js_version);
    }
};

/// Window information
pub const WindowInfo = struct {
    window_id: i64,
    bounds: Bounds,
};

/// Window bounds
pub const Bounds = struct {
    left: ?i32 = null,
    top: ?i32 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    window_state: ?[]const u8 = null,
};

/// Parse bounds from JSON
fn parseBounds(allocator: std.mem.Allocator, obj: std.json.Value) !Bounds {
    _ = allocator;
    return .{
        .left = if (obj.object.get("left")) |v| switch (v) {
            .integer => |i| @intCast(i),
            else => null,
        } else null,
        .top = if (obj.object.get("top")) |v| switch (v) {
            .integer => |i| @intCast(i),
            else => null,
        } else null,
        .width = if (obj.object.get("width")) |v| switch (v) {
            .integer => |i| @intCast(i),
            else => null,
        } else null,
        .height = if (obj.object.get("height")) |v| switch (v) {
            .integer => |i| @intCast(i),
            else => null,
        } else null,
        .window_state = if (obj.object.get("windowState")) |v| switch (v) {
            .string => |s| s,
            else => null,
        } else null,
    };
}
