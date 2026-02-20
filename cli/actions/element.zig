const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const ResolvedElement = types.ResolvedElement;
pub const ElementPosition = types.ElementPosition;

/// Get element position using JavaScript evaluation
pub fn getElementPosition(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !ElementPosition {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        // CSS selector path
        js = try std.fmt.allocPrint(allocator, "{s}({s})", .{ helpers.FIND_BY_CSS_JS, try helpers.escapeJsString(allocator, css) });
    } else {
        // Role-based path
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n|
            try helpers.escapeJsString(allocator, n)
        else
            try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);

        const nth_arg = if (resolved.nth) |n|
            try std.fmt.allocPrint(allocator, "{}", .{n})
        else
            try allocator.dupe(u8, "0");
        defer allocator.free(nth_arg);

        js = try std.fmt.allocPrint(allocator, "{s}('{s}', {s}, {s})", .{ helpers.FIND_BY_ROLE_JS, role, name_arg, nth_arg });
    }

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    // Parse the result object
    if (result.value) |val| {
        if (val == .object) {
            const x = helpers.getFloatFromJson(val.object.get("x"));
            const y = helpers.getFloatFromJson(val.object.get("y"));
            const width = helpers.getFloatFromJson(val.object.get("width"));
            const height = helpers.getFloatFromJson(val.object.get("height"));

            if (x != null and y != null) {
                return ElementPosition{
                    .x = x.?,
                    .y = y.?,
                    .width = width orelse 0,
                    .height = height orelse 0,
                };
            }
        }
    }

    std.debug.print("Error: Element not found\n", .{});
    return error.ElementNotFound;
}

/// Get element center position
pub fn getElementCenter(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !struct { x: f64, y: f64 } {
    const pos = try getElementPosition(session, allocator, resolved);
    return .{
        .x = pos.x + pos.width / 2,
        .y = pos.y + pos.height / 2,
    };
}

/// Click an element
pub fn clickElement(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
    click_count: i32,
) !void {
    const center = try getElementCenter(session, allocator, resolved);

    var input = cdp.Input.init(session);
    try input.click(center.x, center.y, .{
        .button = .left,
        .click_count = click_count,
        .delay_ms = 50,
    });
}

/// Focus an element using JavaScript
pub fn focusElement(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        const escaped = try helpers.escapeJsString(allocator, css);
        defer allocator.free(escaped);
        js = try std.fmt.allocPrint(allocator, "(function(s){{var e=document.querySelector(s);if(e)e.focus();}})({s})", .{escaped});
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try helpers.escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        // Use helper that handles both explicit roles and native elements
        js = try std.fmt.allocPrint(allocator, "{s}('{s}',{s},{});", .{ helpers.FIND_AND_FOCUS_JS, role, name_arg, nth });
    }

    _ = try runtime.evaluate(allocator, js, .{});
}

/// Type text into the focused element
pub fn typeText(
    session: *cdp.Session,
    text: []const u8,
) !void {
    var input = cdp.Input.init(session);
    try input.typeText(text, 10);
}

/// Clear and fill input field using JavaScript (works with Vue/React reactive fields)
pub fn fillElement(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
    text: []const u8,
) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const escaped_text = try helpers.escapeJsString(allocator, text);
    defer allocator.free(escaped_text);

    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        const escaped_css = try helpers.escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator,
            \\(function(sel, val) {{
            \\  var el = document.querySelector(sel);
            \\  if (!el) return false;
            \\  el.focus();
            \\  el.value = '';
            \\  el.dispatchEvent(new Event('input', {{bubbles: true}}));
            \\  el.value = val;
            \\  el.dispatchEvent(new Event('input', {{bubbles: true}}));
            \\  el.dispatchEvent(new Event('change', {{bubbles: true}}));
            \\  return true;
            \\}})({s}, {s})
        , .{ escaped_css, escaped_text });
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try helpers.escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator, "{s}('{s}',{s},{},{s});", .{ helpers.FIND_AND_FILL_JS, role, name_arg, nth, escaped_text });
    }

    _ = try runtime.evaluate(allocator, js, .{});
}

/// Hover over an element
pub fn hoverElement(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !void {
    const center = try getElementCenter(session, allocator, resolved);

    var input = cdp.Input.init(session);
    try input.moveTo(center.x, center.y);
}

/// Select dropdown option by value
pub fn selectOption(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
    value: []const u8,
) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const escaped_val = try helpers.escapeJsString(allocator, value);
    defer allocator.free(escaped_val);

    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        const escaped_css = try helpers.escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator,
            \\(function(s,v){{var e=document.querySelector(s);if(e){{e.value=v;e.dispatchEvent(new Event('change',{{bubbles:true}}))}}}}({s},{s})
        , .{ escaped_css, escaped_val });
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try helpers.escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator, "{s}('{s}',{s},{},{s});", .{ helpers.FIND_AND_SELECT_JS, role, name_arg, nth, escaped_val });
    }

    _ = try runtime.evaluate(allocator, js, .{});
}

/// Check or uncheck a checkbox
pub fn setChecked(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
    checked: bool,
) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const check_str = if (checked) "true" else "false";

    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        const escaped_css = try helpers.escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator,
            \\(function(s,c){{var e=document.querySelector(s);if(e&&e.checked!==c)e.click()}}({s},{s})
        , .{ escaped_css, check_str });
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try helpers.escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator, "{s}('{s}',{s},{},{s});", .{ helpers.FIND_AND_CHECK_JS, role, name_arg, nth, check_str });
    }

    _ = try runtime.evaluate(allocator, js, .{});
}

/// Scroll the page
pub fn scroll(
    session: *cdp.Session,
    delta_x: f64,
    delta_y: f64,
) !void {
    var input = cdp.Input.init(session);
    try input.dispatchMouseEvent(.{
        .type = .mouseWheel,
        .x = 100,
        .y = 100,
        .delta_x = delta_x,
        .delta_y = delta_y,
    });
}

/// Scroll element into view
pub fn scrollIntoView(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        const escaped_css = try helpers.escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator,
            \\(function(s){{var e=document.querySelector(s);if(e)e.scrollIntoView({{block:'center',behavior:'smooth'}})}}({s})
        , .{escaped_css});
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try helpers.escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator, "{s}('{s}',{s},{});", .{ helpers.FIND_AND_SCROLL_JS, role, name_arg, nth });
    }

    _ = try runtime.evaluate(allocator, js, .{});
}

/// Drag from source element to target element
pub fn dragElement(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    src_resolved: *const ResolvedElement,
    tgt_resolved: *const ResolvedElement,
) !void {
    // Get center positions of source and target elements
    const src_center = try getElementCenter(session, allocator, src_resolved);
    const tgt_center = try getElementCenter(session, allocator, tgt_resolved);

    var input = cdp.Input.init(session);

    // Move to source element
    try input.moveTo(src_center.x, src_center.y);

    // Small delay
    var i: u32 = 0;
    while (i < 100000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Mouse down at source
    try input.dispatchMouseEvent(.{
        .type = .mousePressed,
        .x = src_center.x,
        .y = src_center.y,
        .button = .left,
        .click_count = 1,
    });

    // Small delay
    i = 0;
    while (i < 100000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Move to target element (drag)
    try input.dispatchMouseEvent(.{
        .type = .mouseMoved,
        .x = tgt_center.x,
        .y = tgt_center.y,
        .button = .left,
    });

    // Small delay
    i = 0;
    while (i < 100000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Mouse up at target (drop)
    try input.dispatchMouseEvent(.{
        .type = .mouseReleased,
        .x = tgt_center.x,
        .y = tgt_center.y,
        .button = .left,
        .click_count = 1,
    });
}
