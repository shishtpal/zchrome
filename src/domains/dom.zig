const std = @import("std");
const Session = @import("../core/session.zig").Session;
const json_util = @import("../util/json.zig");
const RemoteObject = @import("runtime.zig").RemoteObject;

/// DOM domain client
pub const DOM = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable DOM domain
    pub fn enable(self: *Self) !void {
        _ = try self.session.sendCommand("DOM.enable", .{});
    }

    /// Disable DOM domain
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("DOM.disable", .{});
    }

    /// Get document
    pub fn getDocument(self: *Self, allocator: std.mem.Allocator, depth: ?i32) !Node {
        const result = try self.session.sendCommand("DOM.getDocument", .{
            .depth = depth,
        });

        const root = result.object.get("root") orelse return error.MissingField;
        return try parseNode(allocator, root);
    }

    /// Query selector
    pub fn querySelector(self: *Self, node_id: i64, selector: []const u8) !i64 {
        const result = try self.session.sendCommand("DOM.querySelector", .{
            .node_id = node_id,
            .selector = selector,
        });

        return try json_util.getInt(result, "nodeId");
    }

    /// Query selector all
    pub fn querySelectorAll(self: *Self, allocator: std.mem.Allocator, node_id: i64, selector: []const u8) ![]i64 {
        const result = try self.session.sendCommand("DOM.querySelectorAll", .{
            .node_id = node_id,
            .selector = selector,
        });

        const node_ids = try json_util.getArray(result, "nodeIds");
        var ids = std.ArrayList(i64).init(allocator);
        errdefer ids.deinit();

        for (node_ids) |id| {
            try ids.append(switch (id) {
                .integer => |i| i,
                else => return error.TypeMismatch,
            });
        }

        return ids.toOwnedSlice();
    }

    /// Get outer HTML
    pub fn getOuterHTML(self: *Self, allocator: std.mem.Allocator, node_id: i64) ![]const u8 {
        const result = try self.session.sendCommand("DOM.getOuterHTML", .{
            .node_id = node_id,
        });

        return try allocator.dupe(u8, try json_util.getString(result, "outerHTML"));
    }

    /// Set outer HTML
    pub fn setOuterHTML(self: *Self, node_id: i64, outer_html: []const u8) !void {
        _ = try self.session.sendCommand("DOM.setOuterHTML", .{
            .node_id = node_id,
            .outer_html = outer_html,
        });
    }

    /// Get attributes
    pub fn getAttributes(self: *Self, allocator: std.mem.Allocator, node_id: i64) ![]const u8 {
        const result = try self.session.sendCommand("DOM.getAttributes", .{
            .node_id = node_id,
        });

        const attrs = try json_util.getArray(result, "attributes");
        // Flatten into a single string for simplicity
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();

        for (attrs, 0..) |attr, i| {
            if (i > 0) try buf.append(' ');
            try buf.appendSlice(switch (attr) {
                .string => |s| s,
                else => "",
            });
        }

        return buf.toOwnedSlice();
    }

    /// Set attribute value
    pub fn setAttributeValue(self: *Self, node_id: i64, name: []const u8, value: []const u8) !void {
        _ = try self.session.sendCommand("DOM.setAttributeValue", .{
            .node_id = node_id,
            .name = name,
            .value = value,
        });
    }

    /// Remove attribute
    pub fn removeAttribute(self: *Self, node_id: i64, name: []const u8) !void {
        _ = try self.session.sendCommand("DOM.removeAttribute", .{
            .node_id = node_id,
            .name = name,
        });
    }

    /// Remove node
    pub fn removeNode(self: *Self, node_id: i64) !void {
        _ = try self.session.sendCommand("DOM.removeNode", .{
            .node_id = node_id,
        });
    }

    /// Focus node
    pub fn focus(self: *Self, node_id: i64) !void {
        _ = try self.session.sendCommand("DOM.focus", .{
            .node_id = node_id,
        });
    }

    /// Get box model
    pub fn getBoxModel(self: *Self, allocator: std.mem.Allocator, node_id: i64) !BoxModel {
        const result = try self.session.sendCommand("DOM.getBoxModel", .{
            .node_id = node_id,
        });

        return try parseBoxModel(allocator, result);
    }

    /// Resolve node to remote object
    pub fn resolveNode(self: *Self, allocator: std.mem.Allocator, node_id: i64) !RemoteObject {
        const result = try self.session.sendCommand("DOM.resolveNode", .{
            .node_id = node_id,
        });

        const obj = result.object.get("object") orelse return error.MissingField;
        return parseRemoteObject(allocator, obj);
    }
};

/// DOM node
pub const Node = struct {
    node_id: i64,
    node_type: i64,
    node_name: []const u8,
    node_value: []const u8,
    children: ?[]Node = null,
    attributes: ?[]const u8 = null,
    document_url: ?[]const u8 = null,
    base_url: ?[]const u8 = null,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.node_name);
        allocator.free(self.node_value);
        if (self.children) |children| {
            for (children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children);
        }
        if (self.attributes) |attrs| allocator.free(attrs);
        if (self.document_url) |url| allocator.free(url);
        if (self.base_url) |url| allocator.free(url);
    }
};

/// Box model
pub const BoxModel = struct {
    content: [8]f64,
    padding: [8]f64,
    border: [8]f64,
    margin: [8]f64,
    width: i64,
    height: i64,
};

/// Parse node from JSON
fn parseNode(allocator: std.mem.Allocator, obj: std.json.Value) !Node {
    var children: ?[]Node = null;
    if (obj.object.get("children")) |children_arr| {
        const items = switch (children_arr) {
            .array => |a| a.items,
            else => return error.TypeMismatch,
        };
        var nodes = try allocator.alloc(Node, items.len);
        for (items, 0..) |child, i| {
            nodes[i] = try parseNode(allocator, child);
        }
        children = nodes;
    }

    return .{
        .node_id = try json_util.getInt(obj, "nodeId"),
        .node_type = try json_util.getInt(obj, "nodeType"),
        .node_name = try allocator.dupe(u8, try json_util.getString(obj, "nodeName")),
        .node_value = try allocator.dupe(u8, try json_util.getString(obj, "nodeValue")),
        .children = children,
        .attributes = null,
        .document_url = null,
        .base_url = null,
    };
}

/// Parse box model from JSON
fn parseBoxModel(allocator: std.mem.Allocator, obj: std.json.Value) !BoxModel {
    _ = allocator;

    var model: BoxModel = undefined;

    if (obj.object.get("content")) |content| {
        const arr = switch (content) {
            .array => |a| a.items,
            else => return error.TypeMismatch,
        };
        for (arr, 0..) |v, idx| {
            model.content[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    if (obj.object.get("padding")) |padding| {
        const arr = switch (padding) {
            .array => |a| a.items,
            else => return error.TypeMismatch,
        };
        for (arr, 0..) |v, idx| {
            model.padding[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    if (obj.object.get("border")) |border| {
        const arr = switch (border) {
            .array => |a| a.items,
            else => return error.TypeMismatch,
        };
        for (arr, 0..) |v, idx| {
            model.border[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    if (obj.object.get("margin")) |margin| {
        const arr = switch (margin) {
            .array => |a| a.items,
            else => return error.TypeMismatch,
        };
        for (arr, 0..) |v, idx| {
            model.margin[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    model.width = if (obj.object.get("width")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    } else 0;

    model.height = if (obj.object.get("height")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    } else 0;

    return model;
}

/// Parse remote object (stub - full implementation in runtime.zig)
fn parseRemoteObject(allocator: std.mem.Allocator, obj: std.json.Value) !RemoteObject {
    _ = obj;
    _ = allocator;
    return RemoteObject{
        .type = "object",
    };
}
