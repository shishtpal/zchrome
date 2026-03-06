//! Display functions for cursor information.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const config_mod = @import("../config.zig");

pub const CommandCtx = @import("../commands/types.zig").CommandCtx;

/// JavaScript for getting element info
pub const GET_ELEMENT_INFO_JS = @embedFile("../js/get-element-info.js");

/// Show the currently focused element
pub fn cursorActive(session: *cdp.Session, allocator: std.mem.Allocator) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Replace ELEMENT_VAR with document.activeElement
    const js = try std.mem.replaceOwned(u8, allocator, GET_ELEMENT_INFO_JS, "ELEMENT_VAR", "document.activeElement");
    defer allocator.free(js);

    // Wrap in check for body element
    const wrapped_js = try std.fmt.allocPrint(allocator,
        \\(function() {{
        \\  var el = document.activeElement;
        \\  if (!el || el === document.body) return null;
        \\  return {s}
        \\}})()
    , .{js});
    defer allocator.free(wrapped_js);

    var result = try runtime.evaluate(allocator, wrapped_js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.value) |val| {
        if (val == .object) {
            printElementInfo("Active element", val);
            return;
        }
    }

    std.debug.print("No active element (body has focus)\n", .{});
}

/// Show the element under the mouse cursor
pub fn cursorHover(session: *cdp.Session, ctx: CommandCtx) !void {
    // Get mouse position from config (using session context if available)
    var config = ctx.loadConfig();
    defer config.deinit(ctx.allocator);

    const x = config.last_mouse_x orelse {
        std.debug.print("No mouse position recorded. Use 'mouse move <x> <y>' first.\n", .{});
        return;
    };
    const y = config.last_mouse_y orelse {
        std.debug.print("No mouse position recorded. Use 'mouse move <x> <y>' first.\n", .{});
        return;
    };

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Replace ELEMENT_VAR with document.elementFromPoint(x, y)
    const element_var = try std.fmt.allocPrint(ctx.allocator, "document.elementFromPoint({d}, {d})", .{ x, y });
    defer ctx.allocator.free(element_var);

    const js = try std.mem.replaceOwned(u8, ctx.allocator, GET_ELEMENT_INFO_JS, "ELEMENT_VAR", element_var);
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    std.debug.print("Element at cursor ({d:.0}, {d:.0}):\n", .{ x, y });

    if (result.value) |val| {
        if (val == .object) {
            printElementInfo(null, val);
            return;
        }
    }

    std.debug.print("  (no element found)\n", .{});
}

/// Print element info from JSON value
pub fn printElementInfo(header: ?[]const u8, obj: json.Value) void {
    if (header) |h| {
        std.debug.print("{s}:\n", .{h});
    }

    if (obj.get("type")) |t| {
        if (t == .string) std.debug.print("  type: {s}\n", .{t.string});
    }
    if (obj.get("tag")) |t| {
        if (t == .string) std.debug.print("  tag: {s}\n", .{t.string});
    }
    if (obj.get("role")) |r| {
        if (r == .string) std.debug.print("  role: {s}\n", .{r.string});
    }
    if (obj.get("name")) |n| {
        if (n == .string) std.debug.print("  name: \"{s}\"\n", .{n.string});
    }
    if (obj.get("id")) |i| {
        if (i == .string) std.debug.print("  id: {s}\n", .{i.string});
    }
    if (obj.get("selector")) |s| {
        if (s == .string) std.debug.print("  selector: {s}\n", .{s.string});
    }
    if (obj.get("x")) |x_val| {
        if (obj.get("y")) |y_val| {
            const xf = if (x_val == .float) x_val.float else if (x_val == .integer) @as(f64, @floatFromInt(x_val.integer)) else 0;
            const yf = if (y_val == .float) y_val.float else if (y_val == .integer) @as(f64, @floatFromInt(y_val.integer)) else 0;
            std.debug.print("  position: ({d:.0}, {d:.0})\n", .{ xf, yf });
        }
    }
}
