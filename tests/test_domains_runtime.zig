const std = @import("std");
const cdp = @import("cdp");
const json = cdp.json;

// Remote object representation
pub const RemoteObject = struct {
    type: []const u8,
    subtype: ?[]const u8 = null,
    class_name: ?[]const u8 = null,
    value: ?std.json.Value = null,
    description: ?[]const u8 = null,
    object_id: ?[]const u8 = null,

    pub fn deinit(self: *RemoteObject, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        if (self.subtype) |s| allocator.free(s);
        if (self.class_name) |c| allocator.free(c);
        if (self.description) |d| allocator.free(d);
        if (self.object_id) |o| allocator.free(o);
    }

    pub fn isPrimitive(self: *const RemoteObject) bool {
        return std.mem.eql(u8, self.type, "number") or
            std.mem.eql(u8, self.type, "string") or
            std.mem.eql(u8, self.type, "boolean") or
            std.mem.eql(u8, self.type, "undefined") or
            std.mem.eql(u8, self.type, "null");
    }

    pub fn asString(self: *const RemoteObject) ?[]const u8 {
        if (self.value) |v| {
            return switch (v) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn asNumber(self: *const RemoteObject) ?f64 {
        if (self.value) |v| {
            return switch (v) {
                .float => |f| f,
                .integer => |i| @floatFromInt(i),
                else => null,
            };
        }
        return null;
    }

    pub fn asBool(self: *const RemoteObject) ?bool {
        if (self.value) |v| {
            return switch (v) {
                .bool => |b| b,
                else => null,
            };
        }
        return null;
    }
};

fn parseRemoteObject(allocator: std.mem.Allocator, obj: std.json.Value) !RemoteObject {
    return .{
        .type = try allocator.dupe(u8, try json.getString(obj, "type")),
        .subtype = if (obj.object.get("subtype")) |v| try allocator.dupe(u8, v.string) else null,
        .class_name = if (obj.object.get("className")) |v| try allocator.dupe(u8, v.string) else null,
        .value = obj.object.get("value"),
        .description = if (obj.object.get("description")) |v| try allocator.dupe(u8, v.string) else null,
        .object_id = if (obj.object.get("objectId")) |v| try allocator.dupe(u8, v.string) else null,
    };
}

// RemoteObject Parsing Tests
test "RemoteObject - parse with string value" {
    const json_str = "{\"type\":\"string\",\"value\":\"hello world\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var obj = try parseRemoteObject(std.testing.allocator, parsed.value);
    defer obj.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("string", obj.type);
    try std.testing.expect(obj.value != null);
    try std.testing.expectEqualStrings("hello world", obj.asString().?);
}

test "RemoteObject - parse with number value" {
    const json_str = "{\"type\":\"number\",\"value\":42}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var obj = try parseRemoteObject(std.testing.allocator, parsed.value);
    defer obj.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("number", obj.type);
    try std.testing.expect(obj.asNumber() != null);
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), obj.asNumber().?, 0.001);
}

test "RemoteObject - parse with boolean value" {
    const json_str = "{\"type\":\"boolean\",\"value\":true}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var obj = try parseRemoteObject(std.testing.allocator, parsed.value);
    defer obj.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("boolean", obj.type);
    try std.testing.expect(obj.asBool() == true);
}

test "RemoteObject - parse with undefined type" {
    const json_str = "{\"type\":\"undefined\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var obj = try parseRemoteObject(std.testing.allocator, parsed.value);
    defer obj.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("undefined", obj.type);
    try std.testing.expect(obj.value == null);
}

test "RemoteObject - parse with object type" {
    const json_str = "{\"type\":\"object\",\"className\":\"Object\",\"description\":\"Object\",\"objectId\":\"obj-123\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var obj = try parseRemoteObject(std.testing.allocator, parsed.value);
    defer obj.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("object", obj.type);
    try std.testing.expect(obj.class_name != null);
    try std.testing.expectEqualStrings("Object", obj.class_name.?);
    try std.testing.expect(obj.object_id != null);
    try std.testing.expectEqualStrings("obj-123", obj.object_id.?);
}

test "RemoteObject - parse with subtype" {
    const json_str = "{\"type\":\"object\",\"subtype\":\"array\",\"className\":\"Array\",\"description\":\"Array(3)\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_str, .{});
    defer parsed.deinit();

    var obj = try parseRemoteObject(std.testing.allocator, parsed.value);
    defer obj.deinit(std.testing.allocator);

    try std.testing.expect(obj.subtype != null);
    try std.testing.expectEqualStrings("array", obj.subtype.?);
}

// isPrimitive Tests
test "RemoteObject.isPrimitive - number is primitive" {
    var obj = RemoteObject{ .type = "number" };
    try std.testing.expect(obj.isPrimitive());
}

test "RemoteObject.isPrimitive - string is primitive" {
    var obj = RemoteObject{ .type = "string" };
    try std.testing.expect(obj.isPrimitive());
}

test "RemoteObject.isPrimitive - boolean is primitive" {
    var obj = RemoteObject{ .type = "boolean" };
    try std.testing.expect(obj.isPrimitive());
}

test "RemoteObject.isPrimitive - undefined is primitive" {
    var obj = RemoteObject{ .type = "undefined" };
    try std.testing.expect(obj.isPrimitive());
}

test "RemoteObject.isPrimitive - object is not primitive" {
    var obj = RemoteObject{ .type = "object" };
    try std.testing.expect(!obj.isPrimitive());
}

test "RemoteObject.isPrimitive - function is not primitive" {
    var obj = RemoteObject{ .type = "function" };
    try std.testing.expect(!obj.isPrimitive());
}

// deinit Tests
test "RemoteObject.deinit - frees all memory" {
    var obj = RemoteObject{
        .type = try std.testing.allocator.dupe(u8, "object"),
        .subtype = try std.testing.allocator.dupe(u8, "array"),
        .class_name = try std.testing.allocator.dupe(u8, "Array"),
        .description = try std.testing.allocator.dupe(u8, "Array(3)"),
        .object_id = try std.testing.allocator.dupe(u8, "obj-123"),
    };
    obj.deinit(std.testing.allocator);
}
