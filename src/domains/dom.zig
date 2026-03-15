const std = @import("std");
const json = @import("json");
const Session = @import("../core/session.zig").Session;
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
        try self.session.sendCommandIgnoreResult("DOM.enable", .{});
    }

    /// Disable DOM domain
    pub fn disable(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("DOM.disable", .{});
    }

    /// Options for getDocument
    pub const GetDocumentOptions = struct {
        /// Maximum depth to traverse (-1 for entire subtree)
        depth: ?i32 = null,
        /// Whether to pierce shadow DOM and include shadow roots
        pierce: bool = false,
    };

    /// Get document
    pub fn getDocument(self: *Self, allocator: std.mem.Allocator, options: GetDocumentOptions) !Node {
        const result = try self.session.sendCommand("DOM.getDocument", .{
            .depth = options.depth,
            .pierce = options.pierce,
        });

        const root = result.get("root") orelse return error.MissingField;
        return try parseNode(allocator, root);
    }

    /// Query selector
    pub fn querySelector(self: *Self, node_id: i64, selector: []const u8) !i64 {
        const result = try self.session.sendCommand("DOM.querySelector", .{
            .node_id = node_id,
            .selector = selector,
        });

        return try result.getInt("nodeId");
    }

    /// Query selector all
    pub fn querySelectorAll(self: *Self, allocator: std.mem.Allocator, node_id: i64, selector: []const u8) ![]i64 {
        const result = try self.session.sendCommand("DOM.querySelectorAll", .{
            .node_id = node_id,
            .selector = selector,
        });

        const node_ids = try result.getArray("nodeIds");
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

        return try allocator.dupe(u8, try result.getString("outerHTML"));
    }

    /// Set outer HTML
    pub fn setOuterHTML(self: *Self, node_id: i64, outer_html: []const u8) !void {
        try self.session.sendCommandIgnoreResult("DOM.setOuterHTML", .{
            .node_id = node_id,
            .outer_html = outer_html,
        });
    }

    /// Get attributes
    pub fn getAttributes(self: *Self, allocator: std.mem.Allocator, node_id: i64) ![]const u8 {
        const result = try self.session.sendCommand("DOM.getAttributes", .{
            .node_id = node_id,
        });

        const attrs = try result.getArray("attributes");
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
        try self.session.sendCommandIgnoreResult("DOM.setAttributeValue", .{
            .node_id = node_id,
            .name = name,
            .value = value,
        });
    }

    /// Remove attribute
    pub fn removeAttribute(self: *Self, node_id: i64, name: []const u8) !void {
        try self.session.sendCommandIgnoreResult("DOM.removeAttribute", .{
            .node_id = node_id,
            .name = name,
        });
    }

    /// Remove node
    pub fn removeNode(self: *Self, node_id: i64) !void {
        try self.session.sendCommandIgnoreResult("DOM.removeNode", .{
            .node_id = node_id,
        });
    }

    /// Focus node
    pub fn focus(self: *Self, node_id: i64) !void {
        try self.session.sendCommandIgnoreResult("DOM.focus", .{
            .node_id = node_id,
        });
    }

    /// Set files for file input element (for file uploads)
    pub fn setFileInputFiles(self: *Self, node_id: i64, files: []const []const u8) !void {
        try self.session.sendCommandIgnoreResult("DOM.setFileInputFiles", .{
            .node_id = node_id,
            .files = files,
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

        const obj = result.get("object") orelse return error.MissingField;
        return parseRemoteObject(allocator, obj);
    }

    /// Options for describeNode
    pub const DescribeNodeOptions = struct {
        node_id: ?i64 = null,
        backend_node_id: ?i64 = null,
        object_id: ?[]const u8 = null,
        /// Maximum depth to traverse (-1 for entire subtree)
        depth: ?i32 = null,
        /// Whether to pierce shadow DOM
        pierce: bool = false,
    };

    /// Describe node - returns detailed node info including shadow roots
    pub fn describeNode(self: *Self, allocator: std.mem.Allocator, options: DescribeNodeOptions) !NodeDescription {
        var result = try self.session.sendCommand("DOM.describeNode", .{
            .nodeId = options.node_id,
            .backendNodeId = options.backend_node_id,
            .objectId = options.object_id,
            .depth = options.depth,
            .pierce = options.pierce,
        });
        defer result.deinit(allocator);

        const node = result.get("node") orelse return error.MissingField;
        return try parseNodeDescription(allocator, node);
    }

    /// Request node by backend ID (useful for shadow root traversal)
    pub fn requestNode(self: *Self, object_id: []const u8) !i64 {
        const result = try self.session.sendCommand("DOM.requestNode", .{
            .objectId = object_id,
        });
        return try result.getInt("nodeId");
    }

    /// Get the shadow root of a node (if it has one)
    pub fn getShadowRoot(self: *Self, allocator: std.mem.Allocator, node_id: i64) !?NodeDescription {
        var desc = try self.describeNode(allocator, .{
            .node_id = node_id,
            .depth = 1,
            .pierce = true,
        });

        if (desc.shadow_roots) |roots| {
            if (roots.len > 0) {
                // Return the first shadow root, free the rest
                const first = roots[0];
                for (roots[1..]) |*r| r.deinit(allocator);
                allocator.free(roots);
                desc.shadow_roots = null;
                const result = first;
                desc.deinit(allocator);
                return result;
            }
        }
        desc.deinit(allocator);
        return null;
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

/// Shadow root type
pub const ShadowRootType = enum {
    user_agent,
    open,
    closed,
};

/// Node description (from describeNode)
pub const NodeDescription = struct {
    node_id: i64,
    backend_node_id: i64,
    node_type: i64,
    node_name: []const u8,
    local_name: ?[]const u8 = null,
    node_value: []const u8,
    frame_id: ?[]const u8 = null,
    /// Shadow root type (if this is a shadow root)
    shadow_root_type: ?ShadowRootType = null,
    /// Shadow roots of this element
    shadow_roots: ?[]NodeDescription = null,
    /// Content document for iframes
    content_document: ?*NodeDescription = null,

    pub fn deinit(self: *NodeDescription, allocator: std.mem.Allocator) void {
        allocator.free(self.node_name);
        allocator.free(self.node_value);
        if (self.local_name) |n| allocator.free(n);
        if (self.frame_id) |f| allocator.free(f);
        if (self.shadow_roots) |roots| {
            for (roots) |*r| r.deinit(allocator);
            allocator.free(roots);
        }
        if (self.content_document) |doc| {
            doc.deinit(allocator);
            allocator.destroy(doc);
        }
    }
};

/// Parse node from JSON
fn parseNode(allocator: std.mem.Allocator, obj: json.Value) !Node {
    var children: ?[]Node = null;
    if (obj.get("children")) |children_arr| {
        const items = children_arr.asArray() orelse return error.TypeMismatch;
        var nodes = try allocator.alloc(Node, items.len);
        for (items, 0..) |child, i| {
            nodes[i] = try parseNode(allocator, child);
        }
        children = nodes;
    }

    return .{
        .node_id = try obj.getInt("nodeId"),
        .node_type = try obj.getInt("nodeType"),
        .node_name = try allocator.dupe(u8, try obj.getString("nodeName")),
        .node_value = try allocator.dupe(u8, try obj.getString("nodeValue")),
        .children = children,
        .attributes = null,
        .document_url = null,
        .base_url = null,
    };
}

/// Parse box model from JSON
fn parseBoxModel(allocator: std.mem.Allocator, obj: json.Value) !BoxModel {
    _ = allocator;

    var model: BoxModel = undefined;

    if (obj.get("content")) |content| {
        const arr = content.asArray() orelse return error.TypeMismatch;
        for (arr, 0..) |v, idx| {
            model.content[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    if (obj.get("padding")) |padding| {
        const arr = padding.asArray() orelse return error.TypeMismatch;
        for (arr, 0..) |v, idx| {
            model.padding[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    if (obj.get("border")) |border| {
        const arr = border.asArray() orelse return error.TypeMismatch;
        for (arr, 0..) |v, idx| {
            model.border[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    if (obj.get("margin")) |margin| {
        const arr = margin.asArray() orelse return error.TypeMismatch;
        for (arr, 0..) |v, idx| {
            model.margin[idx] = switch (v) {
                .float => |f| f,
                .integer => |int_val| @floatFromInt(int_val),
                else => 0,
            };
        }
    }

    model.width = if (obj.get("width")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    } else 0;

    model.height = if (obj.get("height")) |v| switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => 0,
    } else 0;

    return model;
}

/// Parse remote object (stub - full implementation in runtime.zig)
fn parseRemoteObject(allocator: std.mem.Allocator, obj: json.Value) !RemoteObject {
    _ = obj;
    _ = allocator;
    return RemoteObject{
        .type = "object",
    };
}

/// Parse node description from JSON
fn parseNodeDescription(allocator: std.mem.Allocator, obj: json.Value) !NodeDescription {
    var shadow_roots: ?[]NodeDescription = null;
    if (obj.get("shadowRoots")) |roots_arr| {
        if (roots_arr.asArray()) |items| {
            var roots = try allocator.alloc(NodeDescription, items.len);
            errdefer allocator.free(roots);
            for (items, 0..) |item, i| {
                roots[i] = try parseNodeDescription(allocator, item);
            }
            shadow_roots = roots;
        }
    }

    var content_document: ?*NodeDescription = null;
    if (obj.get("contentDocument")) |doc| {
        const doc_ptr = try allocator.create(NodeDescription);
        errdefer allocator.destroy(doc_ptr);
        doc_ptr.* = try parseNodeDescription(allocator, doc);
        content_document = doc_ptr;
    }

    var shadow_root_type: ?ShadowRootType = null;
    if (obj.get("shadowRootType")) |srt| {
        if (srt == .string) {
            if (std.mem.eql(u8, srt.string, "open")) {
                shadow_root_type = .open;
            } else if (std.mem.eql(u8, srt.string, "closed")) {
                shadow_root_type = .closed;
            } else if (std.mem.eql(u8, srt.string, "user-agent")) {
                shadow_root_type = .user_agent;
            }
        }
    }

    return .{
        .node_id = try obj.getInt("nodeId"),
        .backend_node_id = if (obj.get("backendNodeId")) |v| switch (v) {
            .integer => |i| i,
            else => 0,
        } else 0,
        .node_type = try obj.getInt("nodeType"),
        .node_name = try allocator.dupe(u8, try obj.getString("nodeName")),
        .local_name = if (obj.get("localName")) |v| try allocator.dupe(u8, v.string) else null,
        .node_value = try allocator.dupe(u8, try obj.getString("nodeValue")),
        .frame_id = if (obj.get("frameId")) |v| try allocator.dupe(u8, v.string) else null,
        .shadow_root_type = shadow_root_type,
        .shadow_roots = shadow_roots,
        .content_document = content_document,
    };
}
