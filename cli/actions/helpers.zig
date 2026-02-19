const std = @import("std");
const types = @import("types.zig");

/// JavaScript to find element by role and name, returns bounding rect
/// Handles both explicit role attributes and implicit roles from HTML elements
pub const FIND_BY_ROLE_JS =
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

        return try std.fmt.allocPrint(allocator,
            "(function(role,name,nth){{var IMPLICIT_ROLES={{'link':'a[href]','button':'button,input[type=\"button\"],input[type=\"submit\"]','textbox':'input[type=\"text\"],input[type=\"email\"],input[type=\"password\"],input[type=\"search\"],input:not([type]),textarea','checkbox':'input[type=\"checkbox\"]','radio':'input[type=\"radio\"]','combobox':'select','heading':'h1,h2,h3,h4,h5,h6'}};var els=Array.from(document.querySelectorAll('[role=\"'+role+'\"]'));if(IMPLICIT_ROLES[role]){{var implicit=Array.from(document.querySelectorAll(IMPLICIT_ROLES[role])).filter(function(e){{return !e.hasAttribute('role')}});els=els.concat(implicit)}}if(name)els=els.filter(function(e){{var label=e.getAttribute('aria-label')||e.textContent.trim();return label===name}});var el=els[nth||0];if(!el)return null;return {s}}})(\"{s}\",{s},{d})"
        , .{ getter_expr, role, name_arg, nth });
    }
}
