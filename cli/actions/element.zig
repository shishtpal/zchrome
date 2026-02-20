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

// ─── Keyboard Functions ─────────────────────────────────────────────────────

/// Key definition with all necessary CDP fields
pub const KeyDef = struct {
    key: []const u8,
    code: []const u8,
    keyCode: i32,
    modifiers: i32 = 0,
};

/// Get key definition for special keys, returns null for regular characters
fn getSpecialKeyDef(key: []const u8) ?struct { code: []const u8, keyCode: i32 } {
    const special_keys = [_]struct { name: []const u8, code: []const u8, keyCode: i32 }{
        .{ .name = "Enter", .code = "Enter", .keyCode = 13 },
        .{ .name = "Tab", .code = "Tab", .keyCode = 9 },
        .{ .name = "Escape", .code = "Escape", .keyCode = 27 },
        .{ .name = "Esc", .code = "Escape", .keyCode = 27 },
        .{ .name = "Backspace", .code = "Backspace", .keyCode = 8 },
        .{ .name = "Delete", .code = "Delete", .keyCode = 46 },
        .{ .name = "Space", .code = "Space", .keyCode = 32 },
        .{ .name = " ", .code = "Space", .keyCode = 32 },
        .{ .name = "ArrowUp", .code = "ArrowUp", .keyCode = 38 },
        .{ .name = "ArrowDown", .code = "ArrowDown", .keyCode = 40 },
        .{ .name = "ArrowLeft", .code = "ArrowLeft", .keyCode = 37 },
        .{ .name = "ArrowRight", .code = "ArrowRight", .keyCode = 39 },
        .{ .name = "Home", .code = "Home", .keyCode = 36 },
        .{ .name = "End", .code = "End", .keyCode = 35 },
        .{ .name = "PageUp", .code = "PageUp", .keyCode = 33 },
        .{ .name = "PageDown", .code = "PageDown", .keyCode = 34 },
        .{ .name = "Insert", .code = "Insert", .keyCode = 45 },
        .{ .name = "F1", .code = "F1", .keyCode = 112 },
        .{ .name = "F2", .code = "F2", .keyCode = 113 },
        .{ .name = "F3", .code = "F3", .keyCode = 114 },
        .{ .name = "F4", .code = "F4", .keyCode = 115 },
        .{ .name = "F5", .code = "F5", .keyCode = 116 },
        .{ .name = "F6", .code = "F6", .keyCode = 117 },
        .{ .name = "F7", .code = "F7", .keyCode = 118 },
        .{ .name = "F8", .code = "F8", .keyCode = 119 },
        .{ .name = "F9", .code = "F9", .keyCode = 120 },
        .{ .name = "F10", .code = "F10", .keyCode = 121 },
        .{ .name = "F11", .code = "F11", .keyCode = 122 },
        .{ .name = "F12", .code = "F12", .keyCode = 123 },
        .{ .name = "Control", .code = "ControlLeft", .keyCode = 17 },
        .{ .name = "Ctrl", .code = "ControlLeft", .keyCode = 17 },
        .{ .name = "Alt", .code = "AltLeft", .keyCode = 18 },
        .{ .name = "Shift", .code = "ShiftLeft", .keyCode = 16 },
        .{ .name = "Meta", .code = "MetaLeft", .keyCode = 91 },
        .{ .name = "Cmd", .code = "MetaLeft", .keyCode = 91 },
    };

    for (special_keys) |sk| {
        if (std.mem.eql(u8, key, sk.name)) {
            return .{ .code = sk.code, .keyCode = sk.keyCode };
        }
    }
    return null;
}

/// Parse key string like "Control+a" into key definition
/// Modifier masks: Alt=1, Ctrl=2, Meta=4, Shift=8
pub fn parseKey(key_str: []const u8) KeyDef {
    var modifiers: i32 = 0;
    var key: []const u8 = key_str;

    // Split by "+" and process each part
    var iter = std.mem.splitSequence(u8, key_str, "+");
    var parts: [8][]const u8 = undefined;
    var count: usize = 0;

    while (iter.next()) |part| {
        if (count < 8) {
            parts[count] = part;
            count += 1;
        }
    }

    // Last part is the key, rest are modifiers
    if (count > 0) {
        key = parts[count - 1];
        for (parts[0 .. count - 1]) |mod| {
            if (std.mem.eql(u8, mod, "Control") or std.mem.eql(u8, mod, "Ctrl")) {
                modifiers |= 2;
            } else if (std.mem.eql(u8, mod, "Alt")) {
                modifiers |= 1;
            } else if (std.mem.eql(u8, mod, "Shift")) {
                modifiers |= 8;
            } else if (std.mem.eql(u8, mod, "Meta") or std.mem.eql(u8, mod, "Cmd")) {
                modifiers |= 4;
            }
        }
    }

    // Look up special key definition
    if (getSpecialKeyDef(key)) |special| {
        return .{
            .key = key,
            .code = special.code,
            .keyCode = special.keyCode,
            .modifiers = modifiers,
        };
    }

    // For regular character keys
    const keyCode: i32 = if (key.len == 1) blk: {
        const c = key[0];
        if (c >= 'a' and c <= 'z') break :blk @as(i32, c - 32);
        if (c >= 'A' and c <= 'Z') break :blk @as(i32, c);
        if (c >= '0' and c <= '9') break :blk @as(i32, c);
        break :blk 0;
    } else 0;

    return .{
        .key = key,
        .code = key,
        .keyCode = keyCode,
        .modifiers = modifiers,
    };
}

/// Press and release a key
pub fn pressKey(session: *cdp.Session, key_str: []const u8) !void {
    const parsed = parseKey(key_str);
    var input = cdp.Input.init(session);

    try input.dispatchKeyEvent(.{
        .type = .keyDown,
        .key = parsed.key,
        .code = parsed.code,
        .windows_virtual_key_code = if (parsed.keyCode != 0) parsed.keyCode else null,
        .modifiers = if (parsed.modifiers != 0) parsed.modifiers else null,
    });
    try input.dispatchKeyEvent(.{
        .type = .keyUp,
        .key = parsed.key,
        .code = parsed.code,
        .windows_virtual_key_code = if (parsed.keyCode != 0) parsed.keyCode else null,
        .modifiers = if (parsed.modifiers != 0) parsed.modifiers else null,
    });
}

/// Hold a key down
pub fn keyDown(session: *cdp.Session, key_str: []const u8) !void {
    const parsed = parseKey(key_str);
    var input = cdp.Input.init(session);

    try input.dispatchKeyEvent(.{
        .type = .keyDown,
        .key = parsed.key,
        .code = parsed.code,
        .windows_virtual_key_code = if (parsed.keyCode != 0) parsed.keyCode else null,
        .modifiers = if (parsed.modifiers != 0) parsed.modifiers else null,
    });
}

/// Release a key
pub fn keyUp(session: *cdp.Session, key_str: []const u8) !void {
    const parsed = parseKey(key_str);
    var input = cdp.Input.init(session);

    try input.dispatchKeyEvent(.{
        .type = .keyUp,
        .key = parsed.key,
        .code = parsed.code,
        .windows_virtual_key_code = if (parsed.keyCode != 0) parsed.keyCode else null,
        .modifiers = if (parsed.modifiers != 0) parsed.modifiers else null,
    });
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
