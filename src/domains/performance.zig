const std = @import("std");
const Session = @import("../core/session.zig").Session;

/// Performance domain client
pub const Performance = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable performance domain
    pub fn enable(self: *Self) !void {
        _ = try self.session.sendCommand("Performance.enable", .{});
    }

    /// Disable performance domain
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("Performance.disable", .{});
    }

    /// Get performance metrics
    pub fn getMetrics(self: *Self, allocator: std.mem.Allocator) ![]Metric {
        const result = try self.session.sendCommand("Performance.getMetrics", .{});

        const metrics_arr = try result.getArray("metrics");
        var metrics = std.ArrayList(Metric).init(allocator);
        errdefer metrics.deinit();

        for (metrics_arr) |m| {
            try metrics.append(.{
                .name = try allocator.dupe(u8, try m.getString("name")),
                .value = try m.getFloat("value"),
            });
        }

        return metrics.toOwnedSlice();
    }
};

/// Performance metric
pub const Metric = struct {
    name: []const u8,
    value: f64,

    pub fn deinit(self: *Metric, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};
