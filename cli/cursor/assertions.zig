//! Assertion execution and variable resolution for macro replay.

const std = @import("std");
const cdp = @import("cdp");
const macro = @import("macro/mod.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");
const dom_mod = @import("../commands/dom.zig");
const session_mod = @import("../session.zig");

/// Resolve an integer value from a string that may be a literal or $variable reference
pub fn resolveIntVar(val: []const u8, variables: *const std.StringHashMap(state.VarValue)) ?i64 {
    if (val.len > 0 and val[0] == '$') {
        // Variable reference
        const var_name = val[1..];
        if (variables.get(var_name)) |v| {
            return switch (v) {
                .int => |i| i,
                .string => |s| std.fmt.parseInt(i64, s, 10) catch null,
                .array, .object => null, // Can't convert to int
            };
        }
        return null;
    }
    // Literal value
    return std.fmt.parseInt(i64, val, 10) catch null;
}

/// Resolve a string value from a string that may be a literal or $variable reference
pub fn resolveStringVar(val: []const u8, variables: *const std.StringHashMap(state.VarValue)) []const u8 {
    if (val.len > 0 and val[0] == '$') {
        // Variable reference
        const var_name = val[1..];
        if (variables.get(var_name)) |v| {
            return switch (v) {
                .string => |s| s,
                .int => val, // Return original if type mismatch
                .array, .object => val, // Return original for complex types
            };
        }
        return val; // Return original if not found
    }
    return val;
}

/// Execute an assertion command, returns true on success, false on failure
pub fn executeAssertion(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
    _: ?*const session_mod.SessionContext,
    variables: *const std.StringHashMap(state.VarValue),
) !bool {
    const timeout_ms = cmd.timeout orelse 5000;
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // 1. Check URL pattern if specified
    if (cmd.url) |url_pattern| {
        const regex_pattern = try utils.globToRegex(allocator, url_pattern);
        defer allocator.free(regex_pattern);

        const js = try std.fmt.allocPrint(allocator, "new RegExp('{s}').test(window.location.href)", .{regex_pattern});
        defer allocator.free(js);

        if (try utils.pollUntilTrue(session, allocator, js, timeout_ms)) {
            return true;
        }
        return false;
    }

    // 2. Check text on page if specified (supports glob patterns with *)
    if (cmd.text) |text| {
        const has_wildcard = std.mem.indexOf(u8, text, "*") != null;

        if (has_wildcard) {
            // Use glob pattern matching via JavaScript regex
            const regex_pattern = try utils.globToRegex(allocator, text);
            defer allocator.free(regex_pattern);

            const js = try std.fmt.allocPrint(allocator, "new RegExp('{s}').test(document.body.innerText)", .{regex_pattern});
            defer allocator.free(js);

            if (try utils.pollUntilTrue(session, allocator, js, timeout_ms)) {
                return true;
            }
        } else {
            const escaped = try utils.escapeForJs(allocator, text);
            defer allocator.free(escaped);

            const js = try std.fmt.allocPrint(allocator, "document.body.innerText.includes('{s}')", .{escaped});
            defer allocator.free(js);

            if (try utils.pollUntilTrue(session, allocator, js, timeout_ms)) {
                return true;
            }
        }
        return false;
    }

    // 3. Check selector-based assertions
    if (cmd.selector) |sel| {
        const escaped_sel = try utils.escapeForJs(allocator, sel);
        defer allocator.free(escaped_sel);

        var js: []const u8 = undefined;

        if (cmd.value) |expected_value| {
            // Check element value/text content matches
            const escaped_val = try utils.escapeForJs(allocator, expected_value);
            defer allocator.free(escaped_val);

            js = try std.fmt.allocPrint(allocator,
                \\(function(s,v){{
                \\  var el = document.querySelector(s);
                \\  if (!el) return false;
                \\  if (el.multiple) {{
                \\    var expected = JSON.parse(v);
                \\    var selected = Array.from(el.selectedOptions).map(function(o){{ return o.value; }});
                \\    return expected.length === selected.length && expected.every(function(e){{ return selected.includes(e); }});
                \\  }}
                \\  return el.value === v || el.textContent.trim() === v;
                \\}})('{s}', '{s}')
            , .{ escaped_sel, escaped_val });
        } else if (cmd.attribute) |attr| {
            // Check attribute value
            const escaped_attr = try utils.escapeForJs(allocator, attr);
            defer allocator.free(escaped_attr);

            if (cmd.contains) |contains_val| {
                const escaped_contains = try utils.escapeForJs(allocator, contains_val);
                defer allocator.free(escaped_contains);
                js = try std.fmt.allocPrint(allocator,
                    \\(function(s,a,c){{
                    \\  var el = document.querySelector(s);
                    \\  if (!el) return false;
                    \\  var av = el.getAttribute(a);
                    \\  return av && av.includes(c);
                    \\}})('{s}', '{s}', '{s}')
                , .{ escaped_sel, escaped_attr, escaped_contains });
            } else {
                js = try std.fmt.allocPrint(allocator,
                    \\(function(s,a){{
                    \\  var el = document.querySelector(s);
                    \\  return el && el.hasAttribute(a);
                    \\}})('{s}', '{s}')
                , .{ escaped_sel, escaped_attr });
            }
        } else {
            // Just check element exists and is visible
            js = try std.fmt.allocPrint(allocator,
                \\(function(s){{
                \\  var el = document.querySelector(s);
                \\  if (!el) return false;
                \\  var style = getComputedStyle(el);
                \\  return style.display !== 'none' && style.visibility !== 'hidden';
                \\}})('{s}')
            , .{escaped_sel});
        }
        defer allocator.free(js);

        if (try utils.pollUntilTrue(session, allocator, js, timeout_ms)) {
            return true;
        }
        return false;
    }

    // 3.5 Count-based assertions (uses querySelectorAll)
    if (cmd.selector) |sel| {
        if (cmd.count != null or cmd.count_min != null or cmd.count_max != null) {
            const escaped_sel = try utils.escapeForJs(allocator, sel);
            defer allocator.free(escaped_sel);

            // Build JavaScript to get count and compare
            var conditions: std.ArrayList(u8) = .empty;
            defer conditions.deinit(allocator);

            try conditions.appendSlice(allocator, "(function(s){var c=document.querySelectorAll(s).length;return ");

            var has_condition = false;
            if (cmd.count) |expected| {
                const cond = try std.fmt.allocPrint(allocator, "c==={}", .{expected});
                defer allocator.free(cond);
                try conditions.appendSlice(allocator, cond);
                has_condition = true;
            }
            if (cmd.count_min) |min| {
                if (has_condition) try conditions.appendSlice(allocator, "&&");
                const cond = try std.fmt.allocPrint(allocator, "c>={}", .{min});
                defer allocator.free(cond);
                try conditions.appendSlice(allocator, cond);
                has_condition = true;
            }
            if (cmd.count_max) |max| {
                if (has_condition) try conditions.appendSlice(allocator, "&&");
                const cond = try std.fmt.allocPrint(allocator, "c<={}", .{max});
                defer allocator.free(cond);
                try conditions.appendSlice(allocator, cond);
                has_condition = true;
            }

            const js = try std.fmt.allocPrint(allocator, "{s}}})('{s}')", .{ conditions.items, escaped_sel });
            defer allocator.free(js);

            if (try utils.pollUntilTrue(session, allocator, js, timeout_ms)) {
                return true;
            }
            return false;
        }
    }

    // 3.6 Variable-based count comparisons (count_gt, count_lt, count_gte, count_lte)
    if (cmd.selector) |sel| {
        if (cmd.count_gt != null or cmd.count_lt != null or cmd.count_gte != null or cmd.count_lte != null) {
            const escaped_sel = try utils.escapeForJs(allocator, sel);
            defer allocator.free(escaped_sel);

            // Get current count
            const count_js = try std.fmt.allocPrint(allocator, "document.querySelectorAll('{s}').length", .{escaped_sel});
            defer allocator.free(count_js);
            var result = try runtime.evaluate(allocator, count_js, .{ .return_by_value = true });
            defer result.deinit(allocator);

            const current_count: i64 = if (result.asNumber()) |num| @intFromFloat(num) else 0;

            // Check count_gt
            if (cmd.count_gt) |expected| {
                const target = resolveIntVar(expected, variables);
                if (target) |t| {
                    if (current_count <= t) return false;
                } else {
                    std.debug.print("    Error: cannot resolve count_gt value: {s}\n", .{expected});
                    return false;
                }
            }
            // Check count_lt
            if (cmd.count_lt) |expected| {
                const target = resolveIntVar(expected, variables);
                if (target) |t| {
                    if (current_count >= t) return false;
                } else {
                    std.debug.print("    Error: cannot resolve count_lt value: {s}\n", .{expected});
                    return false;
                }
            }
            // Check count_gte
            if (cmd.count_gte) |expected| {
                const target = resolveIntVar(expected, variables);
                if (target) |t| {
                    if (current_count < t) return false;
                } else {
                    std.debug.print("    Error: cannot resolve count_gte value: {s}\n", .{expected});
                    return false;
                }
            }
            // Check count_lte
            if (cmd.count_lte) |expected| {
                const target = resolveIntVar(expected, variables);
                if (target) |t| {
                    if (current_count > t) return false;
                } else {
                    std.debug.print("    Error: cannot resolve count_lte value: {s}\n", .{expected});
                    return false;
                }
            }
            return true;
        }
    }

    // 3.7 Variable-based text comparisons (text_eq, text_neq, text_contains_var)
    if (cmd.selector) |sel| {
        if (cmd.text_eq != null or cmd.text_neq != null or cmd.text_contains_var != null) {
            const escaped_sel = try utils.escapeForJs(allocator, sel);
            defer allocator.free(escaped_sel);

            // Get current text
            const text_js = try std.fmt.allocPrint(allocator, "document.querySelector('{s}')?.textContent?.trim()||''", .{escaped_sel});
            defer allocator.free(text_js);
            var result = try runtime.evaluate(allocator, text_js, .{ .return_by_value = true });
            defer result.deinit(allocator);

            const current_text = result.asString() orelse "";

            // Check text_eq
            if (cmd.text_eq) |expected| {
                const target = resolveStringVar(expected, variables);
                if (!std.mem.eql(u8, current_text, target)) return false;
            }
            // Check text_neq
            if (cmd.text_neq) |expected| {
                const target = resolveStringVar(expected, variables);
                if (std.mem.eql(u8, current_text, target)) return false;
            }
            // Check text_contains_var
            if (cmd.text_contains_var) |expected| {
                const target = resolveStringVar(expected, variables);
                if (std.mem.indexOf(u8, current_text, target) == null) return false;
            }
            return true;
        }
    }

    // 3.8 Variable-based value comparisons (value_eq, value_neq)
    if (cmd.selector) |sel| {
        if (cmd.value_eq != null or cmd.value_neq != null) {
            const escaped_sel = try utils.escapeForJs(allocator, sel);
            defer allocator.free(escaped_sel);

            // Get current value
            const val_js = try std.fmt.allocPrint(allocator, "document.querySelector('{s}')?.value||''", .{escaped_sel});
            defer allocator.free(val_js);
            var result = try runtime.evaluate(allocator, val_js, .{ .return_by_value = true });
            defer result.deinit(allocator);

            const current_val = result.asString() orelse "";

            // Check value_eq
            if (cmd.value_eq) |expected| {
                const target = resolveStringVar(expected, variables);
                if (!std.mem.eql(u8, current_val, target)) return false;
            }
            // Check value_neq
            if (cmd.value_neq) |expected| {
                const target = resolveStringVar(expected, variables);
                if (std.mem.eql(u8, current_val, target)) return false;
            }
            return true;
        }
    }

    // 4. Snapshot comparison
    if (cmd.snapshot) |snapshot_path| {
        if (cmd.selector) |sel| {
            // Extract current DOM state
            const current_json = try dom_mod.executeExtract(session, allocator, sel, .dom, false);
            defer allocator.free(current_json);

            // Read expected snapshot file
            const dir = std.Io.Dir.cwd();
            const expected_json = dir.readFileAlloc(io, snapshot_path, allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
                std.debug.print("    Failed to read snapshot file {s}: {}\n", .{ snapshot_path, err });
                return false;
            };
            defer allocator.free(expected_json);

            // Normalize and compare JSON (trim whitespace for comparison)
            const current_trimmed = std.mem.trim(u8, current_json, " \t\n\r");
            const expected_trimmed = std.mem.trim(u8, expected_json, " \t\n\r");

            if (std.mem.eql(u8, current_trimmed, expected_trimmed)) {
                return true;
            }

            std.debug.print("    Snapshot mismatch for {s}\n", .{sel});
            return false;
        }
    }

    // No assertion conditions specified - pass by default
    return true;
}
