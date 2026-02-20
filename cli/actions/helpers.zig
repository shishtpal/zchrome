const std = @import("std");
const types = @import("types.zig");

// JavaScript helpers loaded from external files at compile time
pub const FIND_BY_ROLE_JS = @embedFile("../js/find-by-role.js");
pub const FIND_AND_FOCUS_JS = @embedFile("../js/find-and-focus.js");
pub const FIND_AND_FILL_JS = @embedFile("../js/find-and-fill.js");
pub const FIND_AND_SELECT_JS = @embedFile("../js/find-and-select.js");
pub const FIND_AND_CHECK_JS = @embedFile("../js/find-and-check.js");
pub const FIND_AND_SCROLL_JS = @embedFile("../js/find-and-scroll.js");

/// JavaScript to find element by CSS selector, returns bounding rect
pub const FIND_BY_CSS_JS =
    \\(function(selector) {
    \\  var el = document.querySelector(selector);
    \\  if (!el) return null;
    \\  var rect = el.getBoundingClientRect();
    \\  return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    \\})
;

pub fn escapeJsString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
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

pub fn getFloatFromJson(val: ?std.json.Value) ?f64 {
    if (val) |v| {
        return switch (v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }
    return null;
}

/// JavaScript to find element and get property (handles both CSS and role-based)
pub fn buildGetterJs(
    allocator: std.mem.Allocator,
    resolved: *const types.ResolvedElement,
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

        // Build getter using embedded find-by-role logic with getter expression
        return try std.fmt.allocPrint(allocator,
            \\(function(role,name,nth){{
            \\var IMPLICIT_ROLES={{'link':'a[href]','button':'button,input[type="button"],input[type="submit"],input[type="reset"]','textbox':'input:not([type]),input[type="text"],input[type="email"],input[type="password"],input[type="search"],input[type="tel"],input[type="url"],input[type="number"],textarea,[contenteditable="true"],[contenteditable=""]','checkbox':'input[type="checkbox"]','radio':'input[type="radio"]','combobox':'select','heading':'h1,h2,h3,h4,h5,h6'}};
            \\function queryAll(root,sel){{var r=Array.from(root.querySelectorAll(sel));root.querySelectorAll('*').forEach(function(e){{if(e.shadowRoot)r=r.concat(queryAll(e.shadowRoot,sel))}});return r}}
            \\function getLabel(e){{var a=e.getAttribute('aria-label');if(a)return a;var p=e.getAttribute('placeholder');if(p)return p;var id=e.id;if(id){{var l=document.querySelector('label[for="'+id+'"]');if(l)return l.textContent.trim()}}return e.textContent.trim()}}
            \\var els=queryAll(document,'[role="'+role+'"]');
            \\if(IMPLICIT_ROLES[role]){{var implicit=queryAll(document,IMPLICIT_ROLES[role]).filter(function(e){{return !e.hasAttribute('role')}});els=els.concat(implicit)}}
            \\if(name)els=els.filter(function(e){{return getLabel(e)===name}});
            \\var el=els[nth||0];if(!el)return null;return {s}
            \\}})('{s}',{s},{d})
        , .{ getter_expr, role, name_arg, nth });
    }
}
