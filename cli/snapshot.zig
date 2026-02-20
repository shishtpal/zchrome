const std = @import("std");
const cdp = @import("cdp");

/// Element reference for snapshot
pub const ElementRef = struct {
    ref_id: []const u8,
    selector: []const u8,
    role: []const u8,
    name: ?[]const u8,
    nth: ?usize,

    pub fn deinit(self: *ElementRef, allocator: std.mem.Allocator) void {
        allocator.free(self.ref_id);
        allocator.free(self.selector);
        allocator.free(self.role);
        if (self.name) |n| allocator.free(n);
    }
};

/// Snapshot configuration options
pub const SnapshotOptions = struct {
    interactive: bool = false,
    compact: bool = false,
    max_depth: ?usize = null,
    selector: ?[]const u8 = null,
};

/// Snapshot result with tree and refs
pub const SnapshotResult = struct {
    tree: []const u8,
    refs: std.StringHashMap(ElementRef),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SnapshotResult) void {
        self.allocator.free(self.tree);
        var iter = self.refs.iterator();
        while (iter.next()) |entry| {
            var ref = entry.value_ptr.*;
            ref.deinit(self.allocator);
        }
        self.refs.deinit();
    }
};

/// Snapshot data for JSON serialization
pub const SnapshotData = struct {
    timestamp: i64,
    tree: []const u8,
    refs: std.StringHashMap(ElementRef),
};

/// Interactive element roles that should always get refs
pub const INTERACTIVE_ROLES = [_][]const u8{
    "button",
    "link",
    "textbox",
    "checkbox",
    "radio",
    "combobox",
    "listbox",
    "menuitem",
    "menuitemcheckbox",
    "menuitemradio",
    "option",
    "searchbox",
    "slider",
    "spinbutton",
    "switch",
    "tab",
    "treeitem",
};

/// Content roles that get refs if they have text content
pub const CONTENT_ROLES = [_][]const u8{
    "heading",
    "cell",
    "gridcell",
    "columnheader",
    "rowheader",
    "listitem",
    "article",
    "region",
    "main",
    "navigation",
};

/// Structural roles (filtered in compact mode)
pub const STRUCTURAL_ROLES = [_][]const u8{
    "generic",
    "group",
    "list",
    "table",
    "row",
    "rowgroup",
    "grid",
    "treegrid",
    "menu",
    "menubar",
    "toolbar",
    "tablist",
    "tree",
    "directory",
    "document",
    "application",
    "presentation",
    "none",
};

/// Parsed line from ARIA tree
const ParsedLine = struct {
    role: []const u8,
    name: ?[]const u8,
    suffix: []const u8,
    indent: usize,
};

/// Snapshot processor
pub const SnapshotProcessor = struct {
    allocator: std.mem.Allocator,
    ref_counter: usize,
    role_name_counts: std.StringHashMap(usize),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .ref_counter = 0,
            .role_name_counts = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.role_name_counts.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.role_name_counts.deinit();
    }

    /// Generate next ref ID (e1, e2, e3, etc.)
    fn nextRef(self: *Self) ![]const u8 {
        self.ref_counter += 1;
        return std.fmt.allocPrint(self.allocator, "e{}", .{self.ref_counter});
    }

    /// Get role+name key for tracking duplicates
    fn getRoleNameKey(self: *Self, role: []const u8, name: ?[]const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ role, name orelse "" });
    }

    /// Get index for duplicate role+name combinations
    fn getNextIndex(self: *Self, role: []const u8, name: ?[]const u8) !usize {
        const key = try self.getRoleNameKey(role, name);
        errdefer self.allocator.free(key);

        if (self.role_name_counts.get(key)) |count| {
            self.allocator.free(key);
            const new_key = try self.getRoleNameKey(role, name);
            try self.role_name_counts.put(new_key, count + 1);
            return count;
        } else {
            try self.role_name_counts.put(key, 1);
            return 0;
        }
    }

    /// Build ARIA role-based selector
    fn buildSelector(self: *Self, role: []const u8, name: ?[]const u8) ![]const u8 {
        if (name) |n| {
            // Escape quotes in name
            var escaped: std.ArrayList(u8) = .empty;
            defer escaped.deinit(self.allocator);
            for (n) |c| {
                if (c == '"') {
                    try escaped.appendSlice(self.allocator, "\\\"");
                } else {
                    try escaped.append(self.allocator, c);
                }
            }
            return std.fmt.allocPrint(self.allocator, "getByRole('{s}', {{ name: \"{s}\", exact: true }})", .{ role, escaped.items });
        } else {
            return std.fmt.allocPrint(self.allocator, "getByRole('{s}')", .{role});
        }
    }

    /// Check if role is interactive
    fn isInteractive(role: []const u8) bool {
        for (INTERACTIVE_ROLES) |r| {
            if (std.mem.eql(u8, role, r)) return true;
        }
        return false;
    }

    /// Check if role is content
    fn isContent(role: []const u8) bool {
        for (CONTENT_ROLES) |r| {
            if (std.mem.eql(u8, role, r)) return true;
        }
        return false;
    }

    /// Check if role is structural
    fn isStructural(role: []const u8) bool {
        for (STRUCTURAL_ROLES) |r| {
            if (std.mem.eql(u8, role, r)) return true;
        }
        return false;
    }

    /// Parse a line from ARIA snapshot
    /// Format: "  - role \"name\"" or "  - role"
    fn parseLine(line: []const u8) ?ParsedLine {
        // Count leading spaces for indent
        var indent: usize = 0;
        while (indent < line.len and line[indent] == ' ') : (indent += 1) {}

        // Skip if line is all spaces
        if (indent >= line.len) return null;

        // Find "- " marker
        const trimmed = line[indent..];
        if (!std.mem.startsWith(u8, trimmed, "- ")) return null;

        const after_marker = trimmed[2..];

        // Extract role (word characters until space or quote)
        var role_end: usize = 0;
        while (role_end < after_marker.len and
            after_marker[role_end] != ' ' and
            after_marker[role_end] != '"') : (role_end += 1)
        {}

        if (role_end == 0) return null;

        const role = after_marker[0..role_end];

        // Check for name in quotes
        var name: ?[]const u8 = null;
        var suffix: []const u8 = "";

        if (role_end < after_marker.len) {
            const rest = after_marker[role_end..];
            // Look for quoted string
            if (std.mem.indexOf(u8, rest, "\"")) |quote_start| {
                const after_quote = rest[quote_start + 1 ..];
                if (std.mem.indexOf(u8, after_quote, "\"")) |quote_end| {
                    name = after_quote[0..quote_end];
                    if (quote_start + 1 + quote_end + 1 < rest.len) {
                        suffix = rest[quote_start + 1 + quote_end + 1 ..];
                    }
                }
            }
        }

        return .{
            .role = role,
            .name = name,
            .suffix = suffix,
            .indent = indent / 2, // Convert spaces to depth level
        };
    }

    /// Process ARIA tree and generate refs
    pub fn processAriaTree(self: *Self, aria_tree: []const u8, options: SnapshotOptions) !SnapshotResult {
        var refs = std.StringHashMap(ElementRef).init(self.allocator);
        errdefer {
            var iter = refs.iterator();
            while (iter.next()) |entry| {
                var ref = entry.value_ptr.*;
                ref.deinit(self.allocator);
            }
            refs.deinit();
        }

        var result_lines: std.ArrayList(u8) = .empty;
        errdefer result_lines.deinit(self.allocator);

        var lines_iter = std.mem.splitScalar(u8, aria_tree, '\n');

        while (lines_iter.next()) |line| {
            if (line.len == 0) continue;

            const parsed = parseLine(line) orelse {
                // Keep non-element lines as-is
                try result_lines.appendSlice(self.allocator, line);
                try result_lines.append(self.allocator, '\n');
                continue;
            };

            // Check depth limit
            if (options.max_depth) |max| {
                if (parsed.indent > max) continue;
            }

            const is_interactive = isInteractive(parsed.role);
            const is_content = isContent(parsed.role);
            const is_structural = isStructural(parsed.role);

            // Interactive-only mode
            if (options.interactive and !is_interactive) continue;

            // Compact mode: skip empty structural elements
            if (options.compact and is_structural and parsed.name == null) continue;

            // Determine if element should have ref
            const should_have_ref = is_interactive or (is_content and parsed.name != null);

            if (should_have_ref) {
                const ref_id = try self.nextRef();
                errdefer self.allocator.free(ref_id);

                const selector = try self.buildSelector(parsed.role, parsed.name);
                errdefer self.allocator.free(selector);

                const nth = try self.getNextIndex(parsed.role, parsed.name);

                // Build enhanced line
                const indent_str = try self.allocator.alloc(u8, parsed.indent * 2);
                defer self.allocator.free(indent_str);
                @memset(indent_str, ' ');

                if (parsed.name) |name| {
                    if (nth > 0) {
                        const enhanced = try std.fmt.allocPrint(self.allocator, "{s}- {s} \"{s}\" [ref={s}] [nth={}]{s}\n", .{ indent_str, parsed.role, name, ref_id, nth, parsed.suffix });
                        defer self.allocator.free(enhanced);
                        try result_lines.appendSlice(self.allocator, enhanced);
                    } else {
                        const enhanced = try std.fmt.allocPrint(self.allocator, "{s}- {s} \"{s}\" [ref={s}]{s}\n", .{ indent_str, parsed.role, name, ref_id, parsed.suffix });
                        defer self.allocator.free(enhanced);
                        try result_lines.appendSlice(self.allocator, enhanced);
                    }
                } else {
                    if (nth > 0) {
                        const enhanced = try std.fmt.allocPrint(self.allocator, "{s}- {s} [ref={s}] [nth={}]{s}\n", .{ indent_str, parsed.role, ref_id, nth, parsed.suffix });
                        defer self.allocator.free(enhanced);
                        try result_lines.appendSlice(self.allocator, enhanced);
                    } else {
                        const enhanced = try std.fmt.allocPrint(self.allocator, "{s}- {s} [ref={s}]{s}\n", .{ indent_str, parsed.role, ref_id, parsed.suffix });
                        defer self.allocator.free(enhanced);
                        try result_lines.appendSlice(self.allocator, enhanced);
                    }
                }

                // Store ref
                const ref = ElementRef{
                    .ref_id = try self.allocator.dupe(u8, ref_id),
                    .selector = selector,
                    .role = try self.allocator.dupe(u8, parsed.role),
                    .name = if (parsed.name) |n| try self.allocator.dupe(u8, n) else null,
                    .nth = if (nth > 0) nth else null,
                };
                try refs.put(try self.allocator.dupe(u8, ref_id), ref);
            } else {
                // Keep line as-is
                try result_lines.appendSlice(self.allocator, line);
                try result_lines.append(self.allocator, '\n');
            }
        }

        const tree = if (result_lines.items.len == 0)
            try self.allocator.dupe(u8, "(empty)")
        else
            try result_lines.toOwnedSlice(self.allocator);

        return .{
            .tree = tree,
            .refs = refs,
            .allocator = self.allocator,
        };
    }
};

/// JavaScript code to extract accessibility tree from the DOM (loaded from external file)
pub const SNAPSHOT_JS = @embedFile("js/snapshot.js");

/// Build the JavaScript code with arguments
pub fn buildSnapshotJs(allocator: std.mem.Allocator, selector: ?[]const u8, max_depth: ?usize) ![]const u8 {
    const selector_arg = if (selector) |s|
        try std.fmt.allocPrint(allocator, "'{s}'", .{s})
    else
        try allocator.dupe(u8, "null");
    defer allocator.free(selector_arg);

    const depth_arg = if (max_depth) |d|
        try std.fmt.allocPrint(allocator, "{}", .{d})
    else
        try allocator.dupe(u8, "null");
    defer allocator.free(depth_arg);

    // Replace SEL_ARG and DEPTH_ARG placeholders
    const with_selector = try std.mem.replaceOwned(u8, allocator, SNAPSHOT_JS, "SEL_ARG", selector_arg);
    defer allocator.free(with_selector);

    const with_depth = try std.mem.replaceOwned(u8, allocator, with_selector, "DEPTH_ARG", depth_arg);

    return with_depth;
}

/// Save snapshot to JSON file
pub fn saveSnapshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    result: *SnapshotResult,
) !void {
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");

    // Timestamp (use 0 as placeholder - Zig 0.16 changed time API)
    const timestamp: i64 = 0;
    const ts_str = try std.fmt.allocPrint(allocator, "  \"timestamp\": {},\n", .{timestamp});
    defer allocator.free(ts_str);
    try json_buf.appendSlice(allocator, ts_str);

    // Tree (escaped)
    try json_buf.appendSlice(allocator, "  \"tree\": \"");
    for (result.tree) |c| {
        switch (c) {
            '\\' => try json_buf.appendSlice(allocator, "\\\\"),
            '"' => try json_buf.appendSlice(allocator, "\\\""),
            '\n' => try json_buf.appendSlice(allocator, "\\n"),
            '\r' => try json_buf.appendSlice(allocator, "\\r"),
            '\t' => try json_buf.appendSlice(allocator, "\\t"),
            else => try json_buf.append(allocator, c),
        }
    }
    try json_buf.appendSlice(allocator, "\",\n");

    // Refs
    try json_buf.appendSlice(allocator, "  \"refs\": {\n");

    var first = true;
    var iter = result.refs.iterator();
    while (iter.next()) |entry| {
        if (!first) try json_buf.appendSlice(allocator, ",\n");
        first = false;

        const ref = entry.value_ptr.*;

        // "e1": { ... }
        try json_buf.appendSlice(allocator, "    \"");
        try json_buf.appendSlice(allocator, ref.ref_id);
        try json_buf.appendSlice(allocator, "\": {\n");

        // ref_id
        try json_buf.appendSlice(allocator, "      \"ref_id\": \"");
        try json_buf.appendSlice(allocator, ref.ref_id);
        try json_buf.appendSlice(allocator, "\",\n");

        // selector
        try json_buf.appendSlice(allocator, "      \"selector\": \"");
        for (ref.selector) |c| {
            switch (c) {
                '\\' => try json_buf.appendSlice(allocator, "\\\\"),
                '"' => try json_buf.appendSlice(allocator, "\\\""),
                else => try json_buf.append(allocator, c),
            }
        }
        try json_buf.appendSlice(allocator, "\",\n");

        // role
        try json_buf.appendSlice(allocator, "      \"role\": \"");
        try json_buf.appendSlice(allocator, ref.role);
        try json_buf.appendSlice(allocator, "\"");

        // name (optional)
        if (ref.name) |name| {
            try json_buf.appendSlice(allocator, ",\n      \"name\": \"");
            for (name) |c| {
                switch (c) {
                    '\\' => try json_buf.appendSlice(allocator, "\\\\"),
                    '"' => try json_buf.appendSlice(allocator, "\\\""),
                    else => try json_buf.append(allocator, c),
                }
            }
            try json_buf.appendSlice(allocator, "\"");
        }

        // nth (optional)
        if (ref.nth) |nth| {
            const nth_str = try std.fmt.allocPrint(allocator, ",\n      \"nth\": {}", .{nth});
            defer allocator.free(nth_str);
            try json_buf.appendSlice(allocator, nth_str);
        }

        try json_buf.appendSlice(allocator, "\n    }");
    }

    try json_buf.appendSlice(allocator, "\n  }\n}\n");

    // Write to file
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{
        .sub_path = path,
        .data = json_buf.items,
    }) catch |err| {
        std.debug.print("Error writing snapshot: {}\n", .{err});
        return err;
    };
}

/// Load snapshot from JSON file
pub fn loadSnapshot(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !SnapshotData {
    const dir = std.Io.Dir.cwd();
    var file_buf: [256 * 1024]u8 = undefined;
    const content = try dir.readFile(io, path, &file_buf);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    var data = SnapshotData{
        .timestamp = 0,
        .tree = "",
        .refs = std.StringHashMap(ElementRef).init(allocator),
    };

    if (parsed.value.object.get("timestamp")) |v| {
        if (v == .integer) data.timestamp = v.integer;
    }

    if (parsed.value.object.get("tree")) |v| {
        if (v == .string) data.tree = try allocator.dupe(u8, v.string);
    }

    if (parsed.value.object.get("refs")) |refs_obj| {
        if (refs_obj == .object) {
            var refs_iter = refs_obj.object.iterator();
            while (refs_iter.next()) |entry| {
                const ref_id = entry.key_ptr.*;
                const ref_val = entry.value_ptr.*;

                if (ref_val == .object) {
                    var ref = ElementRef{
                        .ref_id = try allocator.dupe(u8, ref_id),
                        .selector = "",
                        .role = "",
                        .name = null,
                        .nth = null,
                    };

                    if (ref_val.object.get("selector")) |v| {
                        if (v == .string) ref.selector = try allocator.dupe(u8, v.string);
                    }
                    if (ref_val.object.get("role")) |v| {
                        if (v == .string) ref.role = try allocator.dupe(u8, v.string);
                    }
                    if (ref_val.object.get("name")) |v| {
                        if (v == .string) ref.name = try allocator.dupe(u8, v.string);
                    }
                    if (ref_val.object.get("nth")) |v| {
                        if (v == .integer) ref.nth = @intCast(v.integer);
                    }

                    try data.refs.put(try allocator.dupe(u8, ref_id), ref);
                }
            }
        }
    }

    return data;
}
