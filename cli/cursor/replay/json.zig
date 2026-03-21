//! JSON utilities for extract, append, and serialization operations.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");

const macro = @import("../macro/mod.zig");
const state = @import("../state.zig");
const interpolate = @import("interpolate.zig");

/// Extract multiple fields using selector map
pub fn extractFields(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    fields: std.StringArrayHashMapUnmanaged(macro.FieldConfig),
    variables: *const std.StringHashMap(state.VarValue),
) ![]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var json_buf: std.ArrayList(u8) = .empty;
    errdefer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{");

    var first = true;
    for (fields.keys(), fields.values()) |name, config| {
        if (!first) try json_buf.appendSlice(allocator, ",");
        first = false;

        // Interpolate selector variables
        const interpolated_selector = interpolate.interpolateVariables(allocator, config.selector, variables);
        defer if (interpolated_selector) |s| allocator.free(s);
        const selector = interpolated_selector orelse config.selector;

        // Build JavaScript based on extract type
        const js_expr = switch (config.extract_type) {
            .text => try std.fmt.allocPrint(allocator,
                \\(function() {{
                \\  var el = document.querySelector('{s}');
                \\  return el ? el.innerText : null;
                \\}})()
            , .{selector}),
            .html => try std.fmt.allocPrint(allocator,
                \\(function() {{
                \\  var el = document.querySelector('{s}');
                \\  return el ? el.innerHTML : null;
                \\}})()
            , .{selector}),
            .attr => blk: {
                const attr_name = config.attr_name orelse "value";
                break :blk try std.fmt.allocPrint(allocator,
                    \\(function() {{
                    \\  var el = document.querySelector('{s}');
                    \\  return el ? el.getAttribute('{s}') : null;
                    \\}})()
                , .{ selector, attr_name });
            },
            .value => try std.fmt.allocPrint(allocator,
                \\(function() {{
                \\  var el = document.querySelector('{s}');
                \\  return el ? el.value : null;
                \\}})()
            , .{selector}),
        };
        defer allocator.free(js_expr);

        // Execute and get result
        var result = runtime.evaluate(allocator, js_expr, .{ .return_by_value = true }) catch null;
        defer if (result) |*r| r.deinit(allocator);

        // Write field
        try json_buf.appendSlice(allocator, "\n  \"");
        try json_buf.appendSlice(allocator, name);
        try json_buf.appendSlice(allocator, "\": ");

        if (result) |r| {
            if (r.value) |val| {
                switch (val) {
                    .string => |s| {
                        try json_buf.appendSlice(allocator, "\"");
                        try appendJsonEscaped(&json_buf, allocator, s);
                        try json_buf.appendSlice(allocator, "\"");
                    },
                    .null => try json_buf.appendSlice(allocator, "null"),
                    .integer => |i| {
                        const num_str = try std.fmt.allocPrint(allocator, "{}", .{i});
                        defer allocator.free(num_str);
                        try json_buf.appendSlice(allocator, num_str);
                    },
                    .float => |f| {
                        const num_str = try std.fmt.allocPrint(allocator, "{d}", .{f});
                        defer allocator.free(num_str);
                        try json_buf.appendSlice(allocator, num_str);
                    },
                    .bool => |b| try json_buf.appendSlice(allocator, if (b) "true" else "false"),
                    else => try json_buf.appendSlice(allocator, "null"),
                }
            } else {
                try json_buf.appendSlice(allocator, "null");
            }
        } else {
            try json_buf.appendSlice(allocator, "null");
        }
    }

    try json_buf.appendSlice(allocator, "\n}");
    return try json_buf.toOwnedSlice(allocator);
}

/// Escape string for JSON output
pub fn appendJsonEscaped(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
}

/// Append new JSON data to existing file with optional deduplication by key path
pub fn appendWithDedupe(allocator: std.mem.Allocator, io: std.Io, output_path: []const u8, new_json: []const u8, dedupe_key: ?[]const u8) ![]const u8 {
    // Parse new data
    var new_parsed = try json.parse(allocator, new_json, .{});
    defer new_parsed.deinit(allocator);

    // Try to load existing file
    const dir = std.Io.Dir.cwd();
    var file_buf: [512 * 1024]u8 = undefined;
    const existing_content = dir.readFile(io, output_path, &file_buf) catch |err| {
        // File doesn't exist, just return the new JSON
        if (err == error.FileNotFound) {
            return try allocator.dupe(u8, new_json);
        }
        return err;
    };

    // Parse existing data
    var existing_parsed = try json.parse(allocator, existing_content, .{});
    defer existing_parsed.deinit(allocator);

    // Both must be arrays for append to work
    if (existing_parsed != .array) {
        // Existing is not an array - wrap it in an array and append
        return try allocator.dupe(u8, new_json);
    }

    // Build result array
    var result_items: std.ArrayList(json.Value) = .empty;
    defer result_items.deinit(allocator);

    // Add all existing items
    for (existing_parsed.array.items) |item| {
        try result_items.append(allocator, item);
    }

    // Get new items (handle both array and single object)
    const new_items: []const json.Value = if (new_parsed == .array)
        new_parsed.array.items
    else
        &[_]json.Value{new_parsed};

    // Add new items with optional deduplication
    for (new_items) |new_item| {
        if (dedupe_key) |key_path| {
            // Check if this item's key already exists
            const new_key_val = getNestedValue(new_item, key_path);
            var is_duplicate = false;

            for (result_items.items) |existing_item| {
                const existing_key_val = getNestedValue(existing_item, key_path);
                if (valuesEqual(new_key_val, existing_key_val)) {
                    is_duplicate = true;
                    break;
                }
            }

            if (!is_duplicate) {
                try result_items.append(allocator, new_item);
            }
        } else {
            // No deduplication, just append
            try result_items.append(allocator, new_item);
        }
    }

    // Serialize back to JSON
    return try serializeJsonArray(allocator, result_items.items);
}

/// Get a nested value from JSON using dot-separated path (e.g., "attrs.data-user-id")
pub fn getNestedValue(value: json.Value, path: []const u8) ?json.Value {
    var current = value;
    var remaining = path;

    while (remaining.len > 0) {
        // Find next dot or end
        const dot_pos = std.mem.indexOf(u8, remaining, ".");
        const key = if (dot_pos) |pos| remaining[0..pos] else remaining;
        remaining = if (dot_pos) |pos| remaining[pos + 1 ..] else &[_]u8{};

        // Navigate into the object
        if (current != .object) return null;
        const next_val = current.object.get(key) orelse return null;
        current = next_val;
    }

    return current;
}

/// Compare two JSON values for equality (for deduplication)
pub fn valuesEqual(a: ?json.Value, b: ?json.Value) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;

    const av = a.?;
    const bv = b.?;

    return switch (av) {
        .string => |s| bv == .string and std.mem.eql(u8, s, bv.string),
        .integer => |i| bv == .integer and i == bv.integer,
        .float => |f| bv == .float and f == bv.float,
        .bool => |bl| bv == .bool and bl == bv.bool,
        .null => bv == .null,
        else => false, // Don't compare arrays/objects
    };
}

/// Serialize a slice of JSON values as a JSON array string
pub fn serializeJsonArray(allocator: std.mem.Allocator, items: []const json.Value) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "[\n");

    for (items, 0..) |item, i| {
        if (i > 0) try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "  ");
        try serializeJsonValue(allocator, &buf, item, 1);
    }

    try buf.appendSlice(allocator, "\n]");
    return try buf.toOwnedSlice(allocator);
}

/// Serialize a single JSON value to string
pub fn serializeJsonValue(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), value: json.Value, depth: usize) !void {
    _ = depth;
    switch (value) {
        .null => try buf.appendSlice(allocator, "null"),
        .bool => |b| try buf.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |i| {
            const s = try std.fmt.allocPrint(allocator, "{}", .{i});
            defer allocator.free(s);
            try buf.appendSlice(allocator, s);
        },
        .float => |f| {
            const s = try std.fmt.allocPrint(allocator, "{d}", .{f});
            defer allocator.free(s);
            try buf.appendSlice(allocator, s);
        },
        .string => |s| {
            const escaped = try json.escapeString(allocator, s);
            defer allocator.free(escaped);
            try buf.append(allocator, '"');
            try buf.appendSlice(allocator, escaped);
            try buf.append(allocator, '"');
        },
        .array => |arr| {
            try buf.append(allocator, '[');
            for (arr.items, 0..) |item, i| {
                if (i > 0) try buf.appendSlice(allocator, ", ");
                try serializeJsonValue(allocator, buf, item, 0);
            }
            try buf.append(allocator, ']');
        },
        .object => |obj| {
            try buf.append(allocator, '{');
            var first = true;
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                if (!first) try buf.appendSlice(allocator, ", ");
                first = false;
                const escaped = try json.escapeString(allocator, entry.key_ptr.*);
                defer allocator.free(escaped);
                try buf.append(allocator, '"');
                try buf.appendSlice(allocator, escaped);
                try buf.appendSlice(allocator, "\": ");
                try serializeJsonValue(allocator, buf, entry.value_ptr.*, 0);
            }
            try buf.append(allocator, '}');
        },
    }
}
