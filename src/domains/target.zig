const std = @import("std");
const Session = @import("../core/session.zig").Session;
const Connection = @import("../core/connection.zig").Connection;
const json_util = @import("../util/json.zig");

/// Target domain client
pub const Target = struct {
    connection: *Connection,

    const Self = @This();

    pub fn init(connection: *Connection) Self {
        return .{ .connection = connection };
    }

    /// Get all targets
    pub fn getTargets(self: *Self, allocator: std.mem.Allocator) ![]TargetInfo {
        const result = try self.connection.sendCommand("Target.getTargets", .{}, null);

        const target_infos = try json_util.getArray(result, "targetInfos");
        var targets: std.ArrayList(TargetInfo) = .empty;
        errdefer targets.deinit(allocator);

        for (target_infos) |info| {
            try targets.append(allocator, .{
                .target_id = try allocator.dupe(u8, try json_util.getString(info, "targetId")),
                .type = try allocator.dupe(u8, try json_util.getString(info, "type")),
                .title = try allocator.dupe(u8, try json_util.getString(info, "title")),
                .url = try allocator.dupe(u8, try json_util.getString(info, "url")),
                .attached = try json_util.getBool(info, "attached"),
                .opener_id = if (info.object.get("openerId")) |v|
                    try allocator.dupe(u8, v.string)
                else
                    null,
                .browser_context_id = if (info.object.get("browserContextId")) |v|
                    try allocator.dupe(u8, v.string)
                else
                    null,
            });
        }

        return targets.toOwnedSlice(allocator);
    }

    /// Create a new target
    pub fn createTarget(self: *Self, url: []const u8) ![]const u8 {
        const result = try self.connection.sendCommand("Target.createTarget", .{
            .url = url,
        }, null);

        return try json_util.getString(result, "targetId");
    }

    /// Close a target
    pub fn closeTarget(self: *Self, target_id: []const u8) !bool {
        const result = try self.connection.sendCommand("Target.closeTarget", .{
            .target_id = target_id,
        }, null);

        return try json_util.getBool(result, "success");
    }

    /// Attach to a target
    pub fn attachToTarget(self: *Self, target_id: []const u8, flatten: bool) ![]const u8 {
        const result = try self.connection.sendCommand("Target.attachToTarget", .{
            .target_id = target_id,
            .flatten = flatten,
        }, null);

        return try json_util.getString(result, "sessionId");
    }

    /// Detach from a target
    pub fn detachFromTarget(self: *Self, session_id: []const u8) !void {
        _ = try self.connection.sendCommand("Target.detachFromTarget", .{
            .session_id = session_id,
        }, null);
    }

    /// Activate a target
    pub fn activateTarget(self: *Self, target_id: []const u8) !void {
        _ = try self.connection.sendCommand("Target.activateTarget", .{
            .target_id = target_id,
        }, null);
    }

    /// Enable target discovery
    pub fn setDiscoverTargets(self: *Self, discover: bool) !void {
        _ = try self.connection.sendCommand("Target.setDiscoverTargets", .{
            .discover = discover,
        }, null);
    }

    /// Create a browser context
    pub fn createBrowserContext(self: *Self) ![]const u8 {
        const result = try self.connection.sendCommand("Target.createBrowserContext", .{}, null);
        return try json_util.getString(result, "browserContextId");
    }

    /// Dispose a browser context
    pub fn disposeBrowserContext(self: *Self, context_id: []const u8) !void {
        _ = try self.connection.sendCommand("Target.disposeBrowserContext", .{
            .browser_context_id = context_id,
        }, null);
    }
};

/// Target information
pub const TargetInfo = struct {
    target_id: []const u8,
    type: []const u8,
    title: []const u8,
    url: []const u8,
    attached: bool,
    opener_id: ?[]const u8 = null,
    browser_context_id: ?[]const u8 = null,

    pub fn deinit(self: *TargetInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.target_id);
        allocator.free(self.type);
        allocator.free(self.title);
        allocator.free(self.url);
        if (self.opener_id) |id| allocator.free(id);
        if (self.browser_context_id) |id| allocator.free(id);
    }
};
