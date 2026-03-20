//! Tree parsing and display functions

const std = @import("std");
const json = @import("json");
const layout_types = @import("types.zig");

pub const LayoutNode = layout_types.LayoutNode;

/// Parse a layout node from JSON value
pub fn parseLayoutNode(allocator: std.mem.Allocator, val: json.Value) !LayoutNode {
    var node = LayoutNode{
        .path = "",
        .tag = "",
        .id = "",
        .cls = "",
        .text = "",
        .x = 0,
        .y = 0,
        .w = 0,
        .h = 0,
        .children = &[_]LayoutNode{},
    };

    if (val != .object) return node;

    if (val.object.get("path")) |p| {
        if (p == .string) node.path = try allocator.dupe(u8, p.string);
    }
    if (val.object.get("tag")) |t| {
        if (t == .string) node.tag = try allocator.dupe(u8, t.string);
    }
    if (val.object.get("id")) |i| {
        if (i == .string) node.id = try allocator.dupe(u8, i.string);
    }
    if (val.object.get("cls")) |c| {
        if (c == .string) node.cls = try allocator.dupe(u8, c.string);
    }
    if (val.object.get("text")) |t| {
        if (t == .string) node.text = try allocator.dupe(u8, t.string);
    }
    if (val.object.get("x")) |x| {
        if (x == .integer) node.x = x.integer;
    }
    if (val.object.get("y")) |y| {
        if (y == .integer) node.y = y.integer;
    }
    if (val.object.get("w")) |w| {
        if (w == .integer) node.w = w.integer;
    }
    if (val.object.get("h")) |h| {
        if (h == .integer) node.h = h.integer;
    }

    if (val.object.get("children")) |children_val| {
        if (children_val == .array) {
            var children_list: std.ArrayList(LayoutNode) = .empty;
            errdefer {
                for (children_list.items) |*c| c.deinit(allocator);
                children_list.deinit(allocator);
            }

            for (children_val.array.items) |child_val| {
                const child = try parseLayoutNode(allocator, child_val);
                try children_list.append(allocator, child);
            }
            node.children = try children_list.toOwnedSlice(allocator);
        }
    }

    return node;
}

/// Print layout tree recursively with indentation
pub fn printLayoutTree(node: *const LayoutNode, depth: usize) void {
    // Indent
    for (0..depth) |_| {
        std.debug.print("  ", .{});
    }

    // Build tag string with id/class: <div#main.container.active>
    // Path prefix
    if (node.path.len == 0) {
        std.debug.print("[@L] {}x{} @ ({},{}) <{s}", .{
            node.w,
            node.h,
            node.x,
            node.y,
            node.tag,
        });
    } else {
        std.debug.print("[@L{s}] {}x{} @ ({},{}) <{s}", .{
            node.path,
            node.w,
            node.h,
            node.x,
            node.y,
            node.tag,
        });
    }

    // Add #id if present
    if (node.id.len > 0) {
        std.debug.print("#{s}", .{node.id});
    }

    // Add .class if present (show first class only to keep it short)
    if (node.cls.len > 0) {
        // Find first space to get first class
        var first_class = node.cls;
        if (std.mem.indexOfScalar(u8, node.cls, ' ')) |space_idx| {
            first_class = node.cls[0..space_idx];
        }
        std.debug.print(".{s}", .{first_class});
    }

    std.debug.print(">", .{});

    // Add text preview if present
    if (node.text.len > 0) {
        std.debug.print(" \"{s}\"", .{node.text});
    }

    std.debug.print("\n", .{});

    // Print children
    for (node.children) |*child| {
        printLayoutTree(child, depth + 1);
    }
}
