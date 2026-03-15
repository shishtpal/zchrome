const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const snapshot_mod = @import("../snapshot.zig");
const config_mod = @import("../config.zig");
const session_mod = @import("../session.zig");
const helpers = @import("helpers.zig");

pub const ResolvedElement = types.ResolvedElement;

/// Delimiter for deep selector piercing (shadow DOM / iframe)
const PIERCE_DELIMITER = " >>> ";

/// Resolve a selector with full iframe + shadow DOM support
/// This version requires a CDP session for iframe context detection
pub fn resolveSelectorWithCdp(allocator: std.mem.Allocator, io: std.Io, session: *cdp.Session, selector: []const u8, session_ctx: ?*const session_mod.SessionContext) !ResolvedElement {
    // Check for >>> piercing syntax first
    if (std.mem.indexOf(u8, selector, PIERCE_DELIMITER)) |_| {
        return resolveDeepSelectorWithSession(allocator, session, selector);
    }
    // For non-piercing selectors, use the standard resolution
    return resolveSelector(allocator, io, selector, session_ctx);
}

/// Resolve a selector string to element information
/// Handles CSS selectors, @ref notation, and >>> piercing syntax
pub fn resolveSelector(allocator: std.mem.Allocator, io: std.Io, selector: []const u8, session_ctx: ?*const session_mod.SessionContext) !ResolvedElement {
    // Check for >>> piercing syntax first - use shadow-only resolution
    // For iframe support, use resolveSelectorWithCdp instead
    if (std.mem.indexOf(u8, selector, PIERCE_DELIMITER)) |_| {
        return resolveDeepSelectorShadowOnly(allocator, selector);
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

/// Resolve a deep selector with >>> piercing syntax with full iframe + shadow DOM support
/// Uses CDP session to detect element types and get iframe execution contexts
fn resolveDeepSelectorWithSession(allocator: std.mem.Allocator, session: *cdp.Session, selector: []const u8) !ResolvedElement {
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

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Track current context and root expression
    // Note: context_id will be used in Phase 3 for OOP iframes
    const current_context_id: ?i64 = null;
    var root_expr: std.ArrayList(u8) = .empty;
    defer root_expr.deinit(allocator);

    var total_iframe_offset_x: f64 = 0;
    var total_iframe_offset_y: f64 = 0;

    // Process all segments except the last one
    for (segments.items[0 .. segments.items.len - 1], 0..) |segment, i| {
        const escaped = try helpers.escapeJsString(allocator, segment);
        defer allocator.free(escaped);

        // Build the current query expression
        var query_js: []const u8 = undefined;
        if (root_expr.items.len == 0) {
            query_js = try std.fmt.allocPrint(allocator, "document.querySelector({s})", .{escaped});
        } else {
            query_js = try std.fmt.allocPrint(allocator, "{s}.querySelector({s})", .{ root_expr.items, escaped });
        }
        defer allocator.free(query_js);

        // Check what type of element this is (iframe or shadow host)
        const check_js = try std.fmt.allocPrint(allocator,
            \\(function(){{
            \\  var el = {s};
            \\  if (!el) return {{ type: 'notfound' }};
            \\  if (el.tagName === 'IFRAME') {{
            \\    var rect = el.getBoundingClientRect();
            \\    return {{ type: 'iframe', x: rect.x, y: rect.y, name: el.name || '', id: el.id || '' }};
            \\  }}
            \\  if (el.shadowRoot) return {{ type: 'shadow' }};
            \\  return {{ type: 'none' }};
            \\}})()
        , .{query_js});
        defer allocator.free(check_js);

        var result = try runtime.evaluate(allocator, check_js, .{
            .return_by_value = true,
            .context_id = current_context_id,
        });
        defer result.deinit(allocator);

        if (result.value) |val| {
            if (val == .object) {
                const elem_type = if (val.object.get("type")) |t| (if (t == .string) t.string else "none") else "none";

                if (std.mem.eql(u8, elem_type, "notfound")) {
                    std.debug.print("Error: Element not found for selector segment: {s}\n", .{segment});
                    return error.ElementNotFound;
                } else if (std.mem.eql(u8, elem_type, "iframe")) {
                    // It's an iframe - need to get its execution context
                    // Accumulate iframe offset for coordinate adjustment
                    if (val.object.get("x")) |x| {
                        total_iframe_offset_x += helpers.getFloatFromJson(x) orelse 0;
                    }
                    if (val.object.get("y")) |y| {
                        total_iframe_offset_y += helpers.getFloatFromJson(y) orelse 0;
                    }

                    // Get iframe's contentDocument context
                    // For same-origin iframes, we can access contentDocument directly
                    const ctx_js = try std.fmt.allocPrint(allocator,
                        \\(function(){{
                        \\  var el = {s};
                        \\  if (!el || !el.contentDocument) return null;
                        \\  return true;
                        \\}})()
                    , .{query_js});
                    defer allocator.free(ctx_js);

                    var ctx_result = try runtime.evaluate(allocator, ctx_js, .{
                        .return_by_value = true,
                        .context_id = current_context_id,
                    });
                    defer ctx_result.deinit(allocator);

                    // For same-origin iframes, we can just change the root expression
                    // to query within the iframe's contentDocument
                    root_expr.clearRetainingCapacity();
                    try root_expr.appendSlice(allocator, query_js);
                    try root_expr.appendSlice(allocator, ".contentDocument");
                } else if (std.mem.eql(u8, elem_type, "shadow")) {
                    // It's a shadow host
                    if (i == 0 and root_expr.items.len == 0) {
                        try root_expr.appendSlice(allocator, "document.querySelector(");
                        try root_expr.appendSlice(allocator, escaped);
                        try root_expr.appendSlice(allocator, ").shadowRoot");
                    } else {
                        try root_expr.appendSlice(allocator, ".querySelector(");
                        try root_expr.appendSlice(allocator, escaped);
                        try root_expr.appendSlice(allocator, ").shadowRoot");
                    }
                } else {
                    // Element is neither iframe nor shadow host - error
                    std.debug.print("Error: Element '{s}' is not an iframe or shadow host (cannot pierce with >>>)\n", .{segment});
                    return error.InvalidPiercingTarget;
                }
            }
        }
    }

    // The final segment is the actual selector to query within the current context
    const final_selector = segments.items[segments.items.len - 1];

    var resolved = ResolvedElement{
        .css_selector = try allocator.dupe(u8, final_selector),
        .role = null,
        .name = null,
        .nth = null,
        .allocator = allocator,
        .context_id = current_context_id,
    };

    // Set root expression if we have one
    if (root_expr.items.len > 0) {
        resolved.root_expression = try root_expr.toOwnedSlice(allocator);
    }

    // Set iframe offsets if we traversed iframes
    if (total_iframe_offset_x != 0 or total_iframe_offset_y != 0) {
        resolved.iframe_offsets = .{ .x = total_iframe_offset_x, .y = total_iframe_offset_y };
    }

    return resolved;
}

/// Resolve a deep selector with >>> piercing syntax (shadow DOM only, no iframe support)
/// Example: "my-component >>> .inner-button" → query .inner-button inside my-component's shadow root
fn resolveDeepSelectorShadowOnly(allocator: std.mem.Allocator, selector: []const u8) !ResolvedElement {
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
