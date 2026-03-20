//! Layout module types and shared utilities

const std = @import("std");
const json = @import("json");

/// Layout tree node from JavaScript
pub const LayoutNode = struct {
    path: []const u8,
    tag: []const u8,
    id: []const u8,
    cls: []const u8,
    text: []const u8,
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    children: []LayoutNode,

    pub fn deinit(self: *LayoutNode, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.tag);
        allocator.free(self.id);
        allocator.free(self.cls);
        allocator.free(self.text);
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};

/// Extract path from @L selector (e.g., "@L0/1/2" -> "0/1/2", "@L" -> "")
pub fn extractLayoutPath(selector: []const u8) []const u8 {
    if (selector.len >= 2 and selector[0] == '@' and selector[1] == 'L') {
        return selector[2..];
    }
    // If not @L prefixed, assume it's already just the path
    return selector;
}

/// Format element info for display: <tag#id.class>
pub fn formatElementTag(
    tag: []const u8,
    id: []const u8,
    cls: []const u8,
) void {
    std.debug.print("<{s}", .{tag});
    if (id.len > 0) std.debug.print("#{s}", .{id});
    if (cls.len > 0) {
        var first_class = cls;
        if (std.mem.indexOfScalar(u8, cls, ' ')) |space_idx| {
            first_class = cls[0..space_idx];
        }
        std.debug.print(".{s}", .{first_class});
    }
    std.debug.print(">", .{});
}

/// Get string field from JSON object, with default
pub fn getJsonString(obj: json.Value, key: []const u8) []const u8 {
    if (obj == .object) {
        if (obj.object.get(key)) |val| {
            if (val == .string) return val.string;
        }
    }
    return "";
}

/// Get int field from JSON object, with default
pub fn getJsonInt(obj: json.Value, key: []const u8) i64 {
    if (obj == .object) {
        if (obj.object.get(key)) |val| {
            if (val == .integer) return val.integer;
        }
    }
    return 0;
}
