const std = @import("std");

/// Element reference for snapshot (mirrors cli/snapshot.zig)
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

/// Snapshot options (mirrors cli/snapshot.zig)
pub const SnapshotOptions = struct {
    interactive: bool = false,
    compact: bool = false,
    max_depth: ?usize = null,
    selector: ?[]const u8 = null,
};

/// Interactive element roles
pub const INTERACTIVE_ROLES = [_][]const u8{
    "button", "link", "textbox", "checkbox", "radio", "combobox",
    "listbox", "menuitem", "menuitemcheckbox", "menuitemradio",
    "option", "searchbox", "slider", "spinbutton", "switch",
    "tab", "treeitem",
};

/// Content roles
pub const CONTENT_ROLES = [_][]const u8{
    "heading", "cell", "gridcell", "columnheader", "rowheader",
    "listitem", "article", "region", "main", "navigation",
};

/// Structural roles
pub const STRUCTURAL_ROLES = [_][]const u8{
    "generic", "group", "list", "table", "row", "rowgroup",
    "grid", "treegrid", "menu", "menubar", "toolbar", "tablist",
    "tree", "directory", "document", "application", "presentation", "none",
};

fn isInteractive(role: []const u8) bool {
    for (INTERACTIVE_ROLES) |r| {
        if (std.mem.eql(u8, role, r)) return true;
    }
    return false;
}

fn isContent(role: []const u8) bool {
    for (CONTENT_ROLES) |r| {
        if (std.mem.eql(u8, role, r)) return true;
    }
    return false;
}

fn isStructural(role: []const u8) bool {
    for (STRUCTURAL_ROLES) |r| {
        if (std.mem.eql(u8, role, r)) return true;
    }
    return false;
}

const ParsedLine = struct {
    role: []const u8,
    name: ?[]const u8,
    suffix: []const u8,
    indent: usize,
};

fn parseLine(line: []const u8) ?ParsedLine {
    var indent: usize = 0;
    while (indent < line.len and line[indent] == ' ') : (indent += 1) {}
    if (indent >= line.len) return null;
    const trimmed = line[indent..];
    if (!std.mem.startsWith(u8, trimmed, "- ")) return null;
    const after_marker = trimmed[2..];
    var role_end: usize = 0;
    while (role_end < after_marker.len and after_marker[role_end] != ' ' and after_marker[role_end] != '"') : (role_end += 1) {}
    if (role_end == 0) return null;
    const role = after_marker[0..role_end];
    var name: ?[]const u8 = null;
    var suffix: []const u8 = "";
    if (role_end < after_marker.len) {
        const rest = after_marker[role_end..];
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
    return .{ .role = role, .name = name, .suffix = suffix, .indent = indent / 2 };
}

fn buildSelector(allocator: std.mem.Allocator, role: []const u8, name: ?[]const u8) ![]const u8 {
    if (name) |n| {
        var escaped: std.ArrayList(u8) = .empty;
        defer escaped.deinit(allocator);
        for (n) |c| {
            if (c == '"') try escaped.appendSlice(allocator, "\\\"") else try escaped.append(allocator, c);
        }
        return std.fmt.allocPrint(allocator, "getByRole('{s}', {{ name: \"{s}\", exact: true }})", .{ role, escaped.items });
    } else {
        return std.fmt.allocPrint(allocator, "getByRole('{s}')", .{role});
    }
}

// ─── Role Classification Tests ───────────────────────────────────────────────

test "isInteractive - all interactive roles" {
    try std.testing.expect(isInteractive("button"));
    try std.testing.expect(isInteractive("link"));
    try std.testing.expect(isInteractive("textbox"));
    try std.testing.expect(isInteractive("checkbox"));
    try std.testing.expect(isInteractive("radio"));
    try std.testing.expect(isInteractive("combobox"));
    try std.testing.expect(isInteractive("listbox"));
    try std.testing.expect(isInteractive("menuitem"));
    try std.testing.expect(isInteractive("tab"));
    try std.testing.expect(isInteractive("slider"));
    try std.testing.expect(isInteractive("switch"));
    try std.testing.expect(isInteractive("treeitem"));
}

test "isInteractive - non-interactive roles" {
    try std.testing.expect(!isInteractive("heading"));
    try std.testing.expect(!isInteractive("generic"));
    try std.testing.expect(!isInteractive("document"));
    try std.testing.expect(!isInteractive("list"));
}

test "isContent - all content roles" {
    try std.testing.expect(isContent("heading"));
    try std.testing.expect(isContent("cell"));
    try std.testing.expect(isContent("gridcell"));
    try std.testing.expect(isContent("columnheader"));
    try std.testing.expect(isContent("rowheader"));
    try std.testing.expect(isContent("listitem"));
    try std.testing.expect(isContent("article"));
    try std.testing.expect(isContent("region"));
    try std.testing.expect(isContent("main"));
    try std.testing.expect(isContent("navigation"));
}

test "isContent - non-content roles" {
    try std.testing.expect(!isContent("button"));
    try std.testing.expect(!isContent("generic"));
    try std.testing.expect(!isContent("link"));
}

test "isStructural - all structural roles" {
    try std.testing.expect(isStructural("generic"));
    try std.testing.expect(isStructural("group"));
    try std.testing.expect(isStructural("list"));
    try std.testing.expect(isStructural("table"));
    try std.testing.expect(isStructural("row"));
    try std.testing.expect(isStructural("document"));
    try std.testing.expect(isStructural("menu"));
    try std.testing.expect(isStructural("toolbar"));
    try std.testing.expect(isStructural("tablist"));
}

test "isStructural - non-structural roles" {
    try std.testing.expect(!isStructural("button"));
    try std.testing.expect(!isStructural("heading"));
    try std.testing.expect(!isStructural("link"));
}

// ─── parseLine Tests ──────────────────────────────────────────────────────────

test "parseLine - role only" {
    const result = parseLine("- button").?;
    try std.testing.expectEqualStrings("button", result.role);
    try std.testing.expect(result.name == null);
    try std.testing.expectEqual(@as(usize, 0), result.indent);
}

test "parseLine - role with name" {
    const result = parseLine("- button \"Submit\"").?;
    try std.testing.expectEqualStrings("button", result.role);
    try std.testing.expectEqualStrings("Submit", result.name.?);
}

test "parseLine - with indent" {
    const result = parseLine("  - link").?;
    try std.testing.expectEqualStrings("link", result.role);
    try std.testing.expectEqual(@as(usize, 1), result.indent);
}

test "parseLine - with deep indent" {
    const result = parseLine("    - textbox").?;
    try std.testing.expectEqualStrings("textbox", result.role);
    try std.testing.expectEqual(@as(usize, 2), result.indent);
}

test "parseLine - empty line returns null" {
    try std.testing.expect(parseLine("") == null);
}

test "parseLine - whitespace only returns null" {
    try std.testing.expect(parseLine("   ") == null);
}

test "parseLine - no marker returns null" {
    try std.testing.expect(parseLine("button") == null);
}

test "parseLine - with suffix" {
    const result = parseLine("- button \"Click\" [expanded]").?;
    try std.testing.expectEqualStrings("button", result.role);
    try std.testing.expectEqualStrings("Click", result.name.?);
    try std.testing.expectEqualStrings(" [expanded]", result.suffix);
}

test "parseLine - name with spaces" {
    const result = parseLine("- link \"Learn More\"").?;
    try std.testing.expectEqualStrings("link", result.role);
    try std.testing.expectEqualStrings("Learn More", result.name.?);
}

test "parseLine - name with special characters" {
    const result = parseLine("- button \"Click & Drag\"").?;
    try std.testing.expectEqualStrings("button", result.role);
    try std.testing.expectEqualStrings("Click & Drag", result.name.?);
}

// ─── buildSelector Tests ─────────────────────────────────────────────────────

test "buildSelector - role only" {
    const result = try buildSelector(std.testing.allocator, "button", null);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("getByRole('button')", result);
}

test "buildSelector - role with name" {
    const result = try buildSelector(std.testing.allocator, "button", "Submit");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("getByRole('button', { name: \"Submit\", exact: true })", result);
}

test "buildSelector - escapes quotes in name" {
    const result = try buildSelector(std.testing.allocator, "link", "Say \"Hello\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("getByRole('link', { name: \"Say \\\"Hello\\\"\", exact: true })", result);
}

test "buildSelector - various roles" {
    const roles = [_][]const u8{ "link", "textbox", "checkbox", "radio", "combobox" };
    for (roles) |role| {
        const result = try buildSelector(std.testing.allocator, role, null);
        defer std.testing.allocator.free(result);
        try std.testing.expect(std.mem.indexOf(u8, result, role) != null);
    }
}

// ─── ElementRef Tests ─────────────────────────────────────────────────────────

test "ElementRef deinit - frees all memory" {
    var ref = ElementRef{
        .ref_id = try std.testing.allocator.dupe(u8, "e1"),
        .selector = try std.testing.allocator.dupe(u8, "getByRole('button')"),
        .role = try std.testing.allocator.dupe(u8, "button"),
        .name = try std.testing.allocator.dupe(u8, "Submit"),
        .nth = 1,
    };
    ref.deinit(std.testing.allocator);
}

test "ElementRef deinit - null name" {
    var ref = ElementRef{
        .ref_id = try std.testing.allocator.dupe(u8, "e1"),
        .selector = try std.testing.allocator.dupe(u8, "getByRole('button')"),
        .role = try std.testing.allocator.dupe(u8, "button"),
        .name = null,
        .nth = null,
    };
    ref.deinit(std.testing.allocator);
}
