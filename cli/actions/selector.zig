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
        // Check for layout path: @L0/2/1
        if (selector.len > 1 and selector[1] == 'L') {
            const path = selector[2..]; // "0/2/1" or "" for body
            return ResolvedElement{
                .css_selector = null,
                .role = null,
                .name = null,
                .nth = null,
                .layout_path = try allocator.dupe(u8, path),
                .allocator = allocator,
            };
        }

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

/// Parse piercing selector segments split by " >>> "
fn parsePiercingSegments(allocator: std.mem.Allocator, selector: []const u8) !std.ArrayList([]const u8) {
    var segments: std.ArrayList([]const u8) = .empty;
    errdefer segments.deinit(allocator);

    var iter = std.mem.splitSequence(u8, selector, PIERCE_DELIMITER);
    while (iter.next()) |segment| {
        const trimmed = std.mem.trim(u8, segment, " ");
        if (trimmed.len > 0) {
            try segments.append(allocator, trimmed);
        }
    }

    if (segments.items.len < 2) {
        std.debug.print("Error: Invalid piercing selector syntax. Expected 'selector >>> selector'\n", .{});
        segments.deinit(allocator);
        return error.InvalidSelector;
    }

    return segments;
}

/// Append a shadow root traversal step to the root expression
fn appendShadowStep(root_expr: *std.ArrayList(u8), allocator: std.mem.Allocator, escaped: []const u8, is_first: bool) !void {
    if (is_first and root_expr.items.len == 0) {
        try root_expr.appendSlice(allocator, "document.querySelector(");
    } else {
        try root_expr.appendSlice(allocator, ".querySelector(");
    }
    try root_expr.appendSlice(allocator, escaped);
    try root_expr.appendSlice(allocator, ").shadowRoot");
}

/// Resolve a deep selector with >>> piercing syntax with full iframe + shadow DOM support
/// Uses CDP session to detect element types and get iframe execution contexts
fn resolveDeepSelectorWithSession(allocator: std.mem.Allocator, session: *cdp.Session, selector: []const u8) !ResolvedElement {
    var segments = try parsePiercingSegments(allocator, selector);
    defer segments.deinit(allocator);

    var active_session = session;
    var runtime = cdp.Runtime.init(active_session);
    try runtime.enable();

    var root_expr: std.ArrayList(u8) = .empty;
    defer root_expr.deinit(allocator);

    var total_iframe_offset_x: f64 = 0;
    var total_iframe_offset_y: f64 = 0;

    // OOP iframe session tracking
    var oop_frame_session: ?*cdp.Session = null;
    var oop_frame_session_id: ?[]const u8 = null;
    var oop_connection: ?*cdp.Connection = null;
    errdefer {
        if (oop_frame_session_id) |sid| {
            if (oop_connection) |conn| {
                var target = cdp.Target.init(conn);
                target.detachFromTarget(sid) catch {};
            }
            allocator.free(sid);
        }
    }

    for (segments.items[0 .. segments.items.len - 1], 0..) |segment, i| {
        const escaped = try helpers.escapeJsString(allocator, segment);
        defer allocator.free(escaped);

        var query_js: []const u8 = undefined;
        if (root_expr.items.len == 0) {
            query_js = try std.fmt.allocPrint(allocator, "document.querySelector({s})", .{escaped});
        } else {
            query_js = try std.fmt.allocPrint(allocator, "{s}.querySelector({s})", .{ root_expr.items, escaped });
        }
        defer allocator.free(query_js);

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
        });
        defer result.deinit(allocator);

        if (result.value) |val| {
            if (val == .object) {
                const elem_type = if (val.object.get("type")) |t| (if (t == .string) t.string else "none") else "none";

                if (std.mem.eql(u8, elem_type, "notfound")) {
                    std.debug.print("Error: Element not found for selector segment: {s}\n", .{segment});
                    return error.ElementNotFound;
                } else if (std.mem.eql(u8, elem_type, "iframe")) {
                    if (val.object.get("x")) |x| {
                        total_iframe_offset_x += helpers.getFloatFromJson(x) orelse 0;
                    }
                    if (val.object.get("y")) |y| {
                        total_iframe_offset_y += helpers.getFloatFromJson(y) orelse 0;
                    }

                    const ctx_js = try std.fmt.allocPrint(allocator,
                        \\(function(){{
                        \\  var el = {s};
                        \\  if (!el) return {{ accessible: false }};
                        \\  try {{
                        \\    if (el.contentDocument) return {{ accessible: true }};
                        \\  }} catch(e) {{}}
                        \\  return {{ accessible: false, src: el.src || '' }};
                        \\}})()
                    , .{query_js});
                    defer allocator.free(ctx_js);

                    var ctx_result = try runtime.evaluate(allocator, ctx_js, .{
                        .return_by_value = true,
                    });
                    defer ctx_result.deinit(allocator);

                    var is_accessible = false;
                    var iframe_src_owned: ?[]const u8 = null;
                    defer if (iframe_src_owned) |s| allocator.free(s);

                    if (ctx_result.value) |ctx_val| {
                        if (ctx_val == .object) {
                            if (ctx_val.object.get("accessible")) |acc| {
                                is_accessible = if (acc == .bool) acc.bool else false;
                            }
                            if (!is_accessible) {
                                if (ctx_val.object.get("src")) |src| {
                                    if (src == .string and src.string.len > 0) {
                                        iframe_src_owned = try allocator.dupe(u8, src.string);
                                    }
                                }
                            }
                        }
                    }

                    if (is_accessible) {
                        root_expr.clearRetainingCapacity();
                        try root_expr.appendSlice(allocator, query_js);
                        try root_expr.appendSlice(allocator, ".contentDocument");
                    } else {
                        const iframe_src = iframe_src_owned orelse {
                            std.debug.print("Error: Cross-origin iframe without src attribute\n", .{});
                            return error.CrossOriginIframe;
                        };
                        std.debug.print("Note: Cross-origin iframe detected (src: {s}). Attempting to attach...\n", .{iframe_src});

                        var target = cdp.Target.init(active_session.connection);
                        const targets = try target.getTargets(allocator);
                        defer {
                            for (targets) |*t| t.deinit(allocator);
                            allocator.free(targets);
                        }

                        var iframe_target_id: ?[]const u8 = null;
                        for (targets) |t| {
                            if (std.mem.eql(u8, t.type, "iframe") and std.mem.indexOf(u8, t.url, iframe_src) != null) {
                                iframe_target_id = t.target_id;
                                break;
                            }
                        }

                        if (iframe_target_id == null) {
                            std.debug.print("Error: Could not find target for cross-origin iframe. The iframe may need to load first.\n", .{});
                            return error.CrossOriginIframeNotFound;
                        }

                        const frame_session_id = try target.attachToTarget(allocator, iframe_target_id.?, true);
                        errdefer allocator.free(frame_session_id);

                        const frame_session = active_session.connection.getOrCreateSession(frame_session_id) catch |err| {
                            std.debug.print("Error: Could not create session for iframe target: {}\n", .{err});
                            allocator.free(frame_session_id);
                            return error.CrossOriginIframeSessionFailed;
                        };

                        oop_frame_session = frame_session;
                        oop_frame_session_id = frame_session_id;
                        oop_connection = active_session.connection;

                        // Switch to iframe session for subsequent segments
                        active_session = frame_session;
                        runtime = cdp.Runtime.init(active_session);
                        try runtime.enable();

                        root_expr.clearRetainingCapacity();
                        try root_expr.appendSlice(allocator, "document");
                    }
                } else if (std.mem.eql(u8, elem_type, "shadow")) {
                    try appendShadowStep(&root_expr, allocator, escaped, i == 0);
                } else {
                    std.debug.print("Error: Element '{s}' is not an iframe or shadow host (cannot pierce with >>>)\n", .{segment});
                    return error.InvalidPiercingTarget;
                }
            }
        }
    }

    const final_selector = segments.items[segments.items.len - 1];

    var resolved = ResolvedElement{
        .css_selector = try allocator.dupe(u8, final_selector),
        .role = null,
        .name = null,
        .nth = null,
        .allocator = allocator,
    };

    if (root_expr.items.len > 0) {
        resolved.root_expression = try root_expr.toOwnedSlice(allocator);
    }

    if (total_iframe_offset_x != 0 or total_iframe_offset_y != 0) {
        resolved.iframe_offsets = .{ .x = total_iframe_offset_x, .y = total_iframe_offset_y };
    }

    if (oop_frame_session) |frame_session| {
        resolved.frame_session = frame_session;
        resolved.frame_session_id = oop_frame_session_id;
        resolved.connection = oop_connection;
        oop_frame_session_id = null;
    }

    return resolved;
}

/// Resolve a deep selector with >>> piercing syntax (shadow DOM only, no iframe support)
/// Example: "my-component >>> .inner-button" → query .inner-button inside my-component's shadow root
fn resolveDeepSelectorShadowOnly(allocator: std.mem.Allocator, selector: []const u8) !ResolvedElement {
    var segments = try parsePiercingSegments(allocator, selector);
    defer segments.deinit(allocator);

    var root_expr: std.ArrayList(u8) = .empty;
    errdefer root_expr.deinit(allocator);

    for (segments.items[0 .. segments.items.len - 1], 0..) |segment, i| {
        const escaped = try helpers.escapeJsString(allocator, segment);
        defer allocator.free(escaped);
        try appendShadowStep(&root_expr, allocator, escaped, i == 0);
    }

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
