const std = @import("std");
const types = @import("types.zig");
const snapshot_mod = @import("../snapshot.zig");
const config_mod = @import("../config.zig");
const session_mod = @import("../session.zig");
const helpers = @import("helpers.zig");

pub const ResolvedElement = types.ResolvedElement;

/// Delimiter for deep selector piercing (shadow DOM / iframe)
const PIERCE_DELIMITER = " >>> ";

/// Resolve a selector string to element information
/// Handles CSS selectors, @ref notation, and >>> piercing syntax
pub fn resolveSelector(allocator: std.mem.Allocator, io: std.Io, selector: []const u8, session_ctx: ?*const session_mod.SessionContext) !ResolvedElement {
    // Check for >>> piercing syntax first
    if (std.mem.indexOf(u8, selector, PIERCE_DELIMITER)) |_| {
        return resolveDeepSelector(allocator, selector);
    }

    if (selector.len > 0 and selector[0] == '@') {
        // Ref-based selector: load from snapshot
        const ref_id = selector[1..];
        const snapshot_path = if (session_ctx) |ctx| try ctx.snapshotPath() else try config_mod.getSnapshotPath(allocator, io);
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

/// Resolve a deep selector with >>> piercing syntax
/// Example: "my-component >>> .inner-button" → query .inner-button inside my-component's shadow root
fn resolveDeepSelector(allocator: std.mem.Allocator, selector: []const u8) !ResolvedElement {
    // Split by " >>> "
    var segments: std.ArrayList([]const u8) = .empty;
    defer segments.deinit(allocator);

    var iter = std.mem.splitSequence(u8, selector, PIERCE_DELIMITER);
    while (iter.next()) |segment| {
        const trimmed = std.mem.trim(u8, segment, " ");
        if (trimmed.len > 0) {
            try segments.append(allocator, trimmed);
        }
    }

    if (segments.items.len < 2) {
        std.debug.print("Error: Invalid piercing selector syntax. Expected 'selector >>> selector'\n", .{});
        return error.InvalidSelector;
    }

    // Build root_expression by chaining shadow root traversals
    // For "a >>> b >>> c":
    //   root = document.querySelector('a').shadowRoot.querySelector('b').shadowRoot
    //   final selector = c
    var root_expr: std.ArrayList(u8) = .empty;
    errdefer root_expr.deinit(allocator);

    // Process all segments except the last one to build the root expression
    for (segments.items[0 .. segments.items.len - 1], 0..) |segment, i| {
        const escaped = try helpers.escapeJsString(allocator, segment);
        defer allocator.free(escaped);

        if (i == 0) {
            // First segment: document.querySelector('segment').shadowRoot
            try root_expr.appendSlice(allocator, "document.querySelector(");
            try root_expr.appendSlice(allocator, escaped);
            try root_expr.appendSlice(allocator, ").shadowRoot");
        } else {
            // Subsequent segments: .querySelector('segment').shadowRoot
            try root_expr.appendSlice(allocator, ".querySelector(");
            try root_expr.appendSlice(allocator, escaped);
            try root_expr.appendSlice(allocator, ").shadowRoot");
        }
    }

    // The final segment is the actual selector to query within the shadow root
    const final_selector = segments.items[segments.items.len - 1];

    return ResolvedElement{
        .css_selector = try allocator.dupe(u8, final_selector),
        .role = null,
        .name = null,
        .nth = null,
        .allocator = allocator,
        .root_expression = try root_expr.toOwnedSlice(allocator),
    };
}
