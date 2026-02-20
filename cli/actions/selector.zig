const std = @import("std");
const types = @import("types.zig");
const snapshot_mod = @import("../snapshot.zig");
const config_mod = @import("../config.zig");

pub const ResolvedElement = types.ResolvedElement;

/// Resolve a selector string to element information
/// Handles both CSS selectors and @ref notation
pub fn resolveSelector(allocator: std.mem.Allocator, io: std.Io, selector: []const u8) !ResolvedElement {
    if (selector.len > 0 and selector[0] == '@') {
        // Ref-based selector: load from snapshot
        const ref_id = selector[1..];
        const snapshot_path = try config_mod.getSnapshotPath(allocator, io);
        defer allocator.free(snapshot_path);

        var snapshot_data = snapshot_mod.loadSnapshot(allocator, io, snapshot_path) catch |err| {
            std.debug.print("Error loading snapshot: {}. Run 'zchrome snapshot' first.\n", .{err});
            return err;
        };
        defer {
            allocator.free(snapshot_data.tree);
            var iter = snapshot_data.refs.iterator();
            while (iter.next()) |entry| {
                var ref = entry.value_ptr.*;
                ref.deinit(allocator);
                allocator.free(entry.key_ptr.*);
            }
            snapshot_data.refs.deinit();
        }

        const ref = snapshot_data.refs.get(ref_id) orelse {
            std.debug.print("Error: Ref '{s}' not found in snapshot\n", .{ref_id});
            return error.RefNotFound;
        };

        return ResolvedElement{
            .css_selector = null,
            .role = try allocator.dupe(u8, ref.role),
            .name = if (ref.name) |n| try allocator.dupe(u8, n) else null,
            .nth = ref.nth,
            .allocator = allocator,
        };
    } else {
        // CSS selector
        return ResolvedElement{
            .css_selector = try allocator.dupe(u8, selector),
            .role = null,
            .name = null,
            .nth = null,
            .allocator = allocator,
        };
    }
}
