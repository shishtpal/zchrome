const std = @import("std");
const cdp = @import("cdp");
const snapshot_mod = @import("snapshot.zig");
const config_mod = @import("config.zig");

/// Resolved element information
pub const ResolvedElement = struct {
    /// CSS selector or null if using JS-based resolution
    css_selector: ?[]const u8,
    /// Role for JS-based resolution (from snapshot ref)
    role: ?[]const u8,
    /// Name for JS-based resolution (from snapshot ref)
    name: ?[]const u8,
    /// Nth index for disambiguation
    nth: ?usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ResolvedElement) void {
        if (self.css_selector) |s| self.allocator.free(s);
        if (self.role) |r| self.allocator.free(r);
        if (self.name) |n| self.allocator.free(n);
    }
};

/// Element position
pub const ElementPosition = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

/// Resolve a selector string to element information
/// Handles both CSS selectors and @ref notation
pub fn resolveSelector(allocator: std.mem.Allocator, io: std.Io, selector: []const u8) !ResolvedElement {
    if (selector.len > 0 and selector[0] == '@') {
        // Ref-based selector: load from snapshot
        const ref_id = selector[1..];
        const snapshot_path = try config_mod.getSnapshotPath(allocator);
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

/// JavaScript to find element by role and name, returns bounding rect
/// Handles both explicit role attributes and implicit roles from HTML elements
const FIND_BY_ROLE_JS =
    \\(function(role, name, nth) {
    \\  var IMPLICIT_ROLES = {
    \\    'link': 'a[href]',
    \\    'button': 'button, input[type="button"], input[type="submit"]',
    \\    'textbox': 'input[type="text"], input[type="email"], input[type="password"], input[type="search"], input[type="tel"], input[type="url"], input:not([type]), textarea',
    \\    'checkbox': 'input[type="checkbox"]',
    \\    'radio': 'input[type="radio"]',
    \\    'combobox': 'select',
    \\    'listbox': 'select[multiple]',
    \\    'heading': 'h1, h2, h3, h4, h5, h6',
    \\    'img': 'img',
    \\    'list': 'ul, ol',
    \\    'listitem': 'li',
    \\    'navigation': 'nav',
    \\    'main': 'main',
    \\    'form': 'form',
    \\    'table': 'table',
    \\    'row': 'tr',
    \\    'cell': 'td',
    \\    'columnheader': 'th'
    \\  };
    \\  var els = Array.from(document.querySelectorAll('[role="' + role + '"]'));
    \\  if (IMPLICIT_ROLES[role]) {
    \\    var implicit = Array.from(document.querySelectorAll(IMPLICIT_ROLES[role]));
    \\    implicit = implicit.filter(function(el) { return !el.hasAttribute('role'); });
    \\    els = els.concat(implicit);
    \\  }
    \\  if (name) {
    \\    els = els.filter(function(el) {
    \\      var label = el.getAttribute('aria-label') || el.textContent.trim();
    \\      return label === name;
    \\    });
    \\  }
    \\  var el = els[nth || 0];
    \\  if (!el) return null;
    \\  var rect = el.getBoundingClientRect();
    \\  return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    \\})
;

/// JavaScript to find element by CSS selector, returns bounding rect
const FIND_BY_CSS_JS =
    \\(function(selector) {
    \\  var el = document.querySelector(selector);
    \\  if (!el) return null;
    \\  var rect = el.getBoundingClientRect();
    \\  return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    \\})
;

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
        js = try std.fmt.allocPrint(allocator, "{s}({s})", .{ FIND_BY_CSS_JS, try escapeJsString(allocator, css) });
    } else {
        // Role-based path
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n|
            try escapeJsString(allocator, n)
        else
            try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);

        const nth_arg = if (resolved.nth) |n|
            try std.fmt.allocPrint(allocator, "{}", .{n})
        else
            try allocator.dupe(u8, "0");
        defer allocator.free(nth_arg);

        js = try std.fmt.allocPrint(allocator, "{s}('{s}', {s}, {s})", .{ FIND_BY_ROLE_JS, role, name_arg, nth_arg });
    }

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    // Parse the result object
    if (result.value) |val| {
        if (val == .object) {
            const x = getFloatFromJson(val.object.get("x"));
            const y = getFloatFromJson(val.object.get("y"));
            const width = getFloatFromJson(val.object.get("width"));
            const height = getFloatFromJson(val.object.get("height"));

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
        const escaped = try escapeJsString(allocator, css);
        defer allocator.free(escaped);
        js = try std.fmt.allocPrint(allocator, "(function(s){{var e=document.querySelector(s);if(e)e.focus();}})({s})", .{escaped});
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator,
            \\(function(role,name,nth){{var els=Array.from(document.querySelectorAll('[role="'+role+'"]'));if(name)els=els.filter(function(e){{return(e.getAttribute('aria-label')||e.textContent.trim())===name}});var el=els[nth];if(el)el.focus()}})('{s}',{s},{})
        , .{ role, name_arg, nth });
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

/// Clear input field (select all + delete)
pub fn clearField(session: *cdp.Session) !void {
    var input = cdp.Input.init(session);
    // Ctrl+A to select all
    try input.dispatchKeyEvent(.{
        .type = .keyDown,
        .key = "a",
        .code = "KeyA",
        .modifiers = 2, // Ctrl
    });
    try input.dispatchKeyEvent(.{
        .type = .keyUp,
        .key = "a",
        .code = "KeyA",
        .modifiers = 2,
    });
    // Delete
    try input.press("Backspace");
}

/// Fill input field (clear + type)
pub fn fillElement(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
    text: []const u8,
) !void {
    try focusElement(session, allocator, resolved);
    // Sleep using spinloop (Zig 0.16 changed time API)
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }
    try clearField(session);
    i = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }
    try typeText(session, text);
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

    const escaped_val = try escapeJsString(allocator, value);
    defer allocator.free(escaped_val);

    var js: []const u8 = undefined;
    defer allocator.free(js);

    if (resolved.css_selector) |css| {
        const escaped_css = try escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator,
            \\(function(s,v){{var e=document.querySelector(s);if(e){{e.value=v;e.dispatchEvent(new Event('change',{{bubbles:true}}))}}}}({s},{s})
        , .{ escaped_css, escaped_val });
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator,
            \\(function(role,name,nth,v){{var els=Array.from(document.querySelectorAll('[role="'+role+'"]'));if(name)els=els.filter(function(e){{return(e.getAttribute('aria-label')||e.textContent.trim())===name}});var el=els[nth];if(el){{el.value=v;el.dispatchEvent(new Event('change',{{bubbles:true}}))}}}})('{s}',{s},{},{s})
        , .{ role, name_arg, nth, escaped_val });
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
        const escaped_css = try escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator,
            \\(function(s,c){{var e=document.querySelector(s);if(e&&e.checked!==c)e.click()}}({s},{s})
        , .{ escaped_css, check_str });
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator,
            \\(function(role,name,nth,c){{var els=Array.from(document.querySelectorAll('[role="'+role+'"]'));if(name)els=els.filter(function(e){{return(e.getAttribute('aria-label')||e.textContent.trim())===name}});var el=els[nth];if(el&&el.checked!==c)el.click()}})('{s}',{s},{},{s})
        , .{ role, name_arg, nth, check_str });
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
        const escaped_css = try escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        js = try std.fmt.allocPrint(allocator,
            \\(function(s){{var e=document.querySelector(s);if(e)e.scrollIntoView({{block:'center',behavior:'smooth'}})}}({s})
        , .{escaped_css});
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        js = try std.fmt.allocPrint(allocator,
            \\(function(role,name,nth){{var els=Array.from(document.querySelectorAll('[role="'+role+'"]'));if(name)els=els.filter(function(e){{return(e.getAttribute('aria-label')||e.textContent.trim())===name}});var el=els[nth];if(el)el.scrollIntoView({{block:'center',behavior:'smooth'}})}})('{s}',{s},{})
        , .{ role, name_arg, nth });
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

// ─── Helpers ────────────────────────────────────────────────────────────────

fn escapeJsString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }
    try result.append(allocator, '"');

    return result.toOwnedSlice(allocator);
}

fn getFloatFromJson(val: ?std.json.Value) ?f64 {
    if (val) |v| {
        return switch (v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }
    return null;
}

// ─── Getter Functions ───────────────────────────────────────────────────────

/// JavaScript to find element and get property (handles both CSS and role-based)
fn buildGetterJs(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
    getter_expr: []const u8,
) ![]const u8 {
    if (resolved.css_selector) |css| {
        const escaped_css = try escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        return try std.fmt.allocPrint(allocator,
            "(function(s){{var el=document.querySelector(s);if(!el)return null;return {s}}})({s})"
        , .{ getter_expr, escaped_css });
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        return try std.fmt.allocPrint(allocator,
            "(function(role,name,nth){{var IMPLICIT_ROLES={{'link':'a[href]','button':'button,input[type=\"button\"],input[type=\"submit\"]','textbox':'input[type=\"text\"],input[type=\"email\"],input[type=\"password\"],input[type=\"search\"],input:not([type]),textarea','checkbox':'input[type=\"checkbox\"]','radio':'input[type=\"radio\"]','combobox':'select','heading':'h1,h2,h3,h4,h5,h6'}};var els=Array.from(document.querySelectorAll('[role=\"'+role+'\"]'));if(IMPLICIT_ROLES[role]){{var implicit=Array.from(document.querySelectorAll(IMPLICIT_ROLES[role])).filter(function(e){{return !e.hasAttribute('role')}});els=els.concat(implicit)}}if(name)els=els.filter(function(e){{var label=e.getAttribute('aria-label')||e.textContent.trim();return label===name}});var el=els[nth||0];if(!el)return null;return {s}}})(\"{s}\",{s},{d})"
        , .{ getter_expr, role, name_arg, nth });
    }
}

/// Get text content of an element
pub fn getText(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !?[]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try buildGetterJs(allocator, resolved, "el.textContent.trim()");
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}

/// Get innerHTML of an element
pub fn getHtml(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !?[]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try buildGetterJs(allocator, resolved, "el.innerHTML");
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}

/// Get value of an input element
pub fn getValue(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !?[]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try buildGetterJs(allocator, resolved, "el.value||''");
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}

/// Get attribute of an element
pub fn getAttribute(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
    attr_name: []const u8,
) !?[]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const escaped_attr = try escapeJsString(allocator, attr_name);
    defer allocator.free(escaped_attr);

    const getter_expr = try std.fmt.allocPrint(allocator, "el.getAttribute({s})", .{escaped_attr});
    defer allocator.free(getter_expr);

    const js = try buildGetterJs(allocator, resolved, getter_expr);
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}

/// Get page title
pub fn getPageTitle(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var result = try runtime.evaluate(allocator, "document.title", .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return try allocator.dupe(u8, "");
}

/// Get current URL
pub fn getPageUrl(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var result = try runtime.evaluate(allocator, "location.href", .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return try allocator.dupe(u8, "");
}

/// Count matching elements
pub fn getCount(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    selector: []const u8,
) !usize {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const escaped_sel = try escapeJsString(allocator, selector);
    defer allocator.free(escaped_sel);

    const js = try std.fmt.allocPrint(allocator, "document.querySelectorAll({s}).length", .{escaped_sel});
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.value) |val| {
        if (val == .integer) {
            return @intCast(val.integer);
        }
    }
    return 0;
}

/// Get computed styles of an element (all styles as JSON)
pub fn getStyles(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !?[]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const getter_expr = "(function(){var s=getComputedStyle(el);var r={};for(var i=0;i<s.length;i++){var p=s[i];r[p]=s.getPropertyValue(p)}return JSON.stringify(r)})()";

    const js = try buildGetterJs(allocator, resolved, getter_expr);
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}
