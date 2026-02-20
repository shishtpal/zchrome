const std = @import("std");
const cdp = @import("cdp");
const json = cdp.json;

// Node in the DOM tree
pub const Node = struct {
    node_id: i32,
    node_type: i32,
    node_name: []const u8,
    node_value: []const u8,
    child_node_count: ?i32 = null,
    children: ?[]Node = null,
    attributes: ?[][]const u8 = null,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.node_name);
        allocator.free(self.node_value);
        if (self.children) |children| {
            for (children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children);
        }
        if (self.attributes) |attrs| {
            for (attrs) |attr| allocator.free(attr);
            allocator.free(attrs);
        }
    }
};

fn parseNode(allocator: std.mem.Allocator, obj: std.json.Value) !Node {
    var node = Node{
        .node_id = @intCast(try json.getInt(obj, "nodeId")),
        .node_type = @intCast(try json.getInt(obj, "nodeType")),
        .node_name = try allocator.dupe(u8, try json.getString(obj, "nodeName")),
        .node_value = try allocator.dupe(u8, try json.getString(obj, "nodeValue")),
        .child_node_count = if (obj.object.get("childNodeCount")) |v| @intCast(v.integer) else null,
        .children = null,
        .attributes = null,
    };

    // Parse children if present
    if (obj.object.get("children")) |children_val| {
        if (children_val == .array) {
            var children = std.ArrayList(Node).initCapacity(allocator, children_val.array.items.len) catch return node;
            for (children_val.array.items) |child| {
                children.appendAssumeCapacity(try parseNode(allocator, child));
            }
            node.children = children.toOwnedSlice(allocator) catch null;
        }
    }

    // Parse attributes if present
    if (obj.object.get("attributes")) |attrs_val| {
        if (attrs_val == .array) {
            var attrs = std.ArrayList([]const u8).initCapacity(allocator, attrs_val.array.items.len) catch return node;
            for (attrs_val.array.items) |attr| {
                attrs.appendAssumeCapacity(try allocator.dupe(u8, attr.string));
            }
            node.attributes = attrs.toOwnedSlice(allocator) catch null;
        }
    }

    return node;
}

// Node Parsing Tests
test "Node - parse basic node" {
    const json_str =
        \\{
        \\  "nodeId": 1,
        \\  "nodeType": 9,
        \\  "nodeName": "#document",
        \\  "nodeValue": "",
        \\  "childNodeCount": 2
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var node = try parseNode(std.testing.allocator, parsed.value);
    defer node.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 1), node.node_id);
    try std.testing.expectEqual(@as(i32, 9), node.node_type);
    try std.testing.expectEqualStrings("#document", node.node_name);
    try std.testing.expectEqualStrings("", node.node_value);
    try std.testing.expect(node.child_node_count != null);
    try std.testing.expectEqual(@as(i32, 2), node.child_node_count.?);
}

test "Node - parse element node" {
    const json_str =
        \\{
        \\  "nodeId": 42,
        \\  "nodeType": 1,
        \\  "nodeName": "DIV",
        \\  "nodeValue": "",
        \\  "childNodeCount": 3
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var node = try parseNode(std.testing.allocator, parsed.value);
    defer node.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 1), node.node_type);
    try std.testing.expectEqualStrings("DIV", node.node_name);
}

test "Node - parse text node" {
    const json_str =
        \\{
        \\  "nodeId": 5,
        \\  "nodeType": 3,
        \\  "nodeName": "#text",
        \\  "nodeValue": "Hello, World!"
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var node = try parseNode(std.testing.allocator, parsed.value);
    defer node.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 3), node.node_type);
    try std.testing.expectEqualStrings("#text", node.node_name);
    try std.testing.expectEqualStrings("Hello, World!", node.node_value);
}

test "Node - parse with attributes" {
    const json_str =
        \\{
        \\  "nodeId": 10,
        \\  "nodeType": 1,
        \\  "nodeName": "INPUT",
        \\  "nodeValue": "",
        \\  "attributes": ["type", "text", "id", "email", "name", "email"]
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var node = try parseNode(std.testing.allocator, parsed.value);
    defer node.deinit(std.testing.allocator);

    try std.testing.expect(node.attributes != null);
    try std.testing.expectEqual(@as(usize, 6), node.attributes.?.len);
    try std.testing.expectEqualStrings("type", node.attributes.?[0]);
    try std.testing.expectEqualStrings("text", node.attributes.?[1]);
}

// querySelector Response Tests
test "querySelector - parse node ID from response" {
    const json_str = "{\"nodeId\":42}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const node_id = try json.getInt(parsed.value, "nodeId");
    try std.testing.expectEqual(@as(i64, 42), node_id);
}

// getOuterHTML Response Tests
test "getOuterHTML - parse HTML from response" {
    const json_str = "{\"outerHTML\":\"<div class=\\\"container\\\"><h1>Hello</h1></div>\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    const html = try json.getString(parsed.value, "outerHTML");
    try std.testing.expectEqualStrings("<div class=\"container\"><h1>Hello</h1></div>", html);
}
