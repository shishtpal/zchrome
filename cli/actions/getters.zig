const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const ResolvedElement = types.ResolvedElement;

/// Get text content of an element
pub fn getText(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    resolved: *const ResolvedElement,
) !?[]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try helpers.buildGetterJs(allocator, resolved, "el.textContent.trim()");
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

    const js = try helpers.buildGetterJs(allocator, resolved, "el.innerHTML");
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

    const js = try helpers.buildGetterJs(allocator, resolved, "el.value||''");
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

    const escaped_attr = try helpers.escapeJsString(allocator, attr_name);
    defer allocator.free(escaped_attr);

    const getter_expr = try std.fmt.allocPrint(allocator, "el.getAttribute({s})", .{escaped_attr});
    defer allocator.free(getter_expr);

    const js = try helpers.buildGetterJs(allocator, resolved, getter_expr);
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

    const escaped_sel = try helpers.escapeJsString(allocator, selector);
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

    const js = try helpers.buildGetterJs(allocator, resolved, getter_expr);
    defer allocator.free(js);

    var result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer result.deinit(allocator);

    if (result.asString()) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}
