/// Mock connection for testing CDP clients without a real browser
const std = @import("std");
const protocol = @import("cdp").protocol;

/// Queued response for mock
pub const MockResponse = struct {
    method: []const u8,
    response_json: []const u8,
};

/// Mock connection that returns pre-configured responses
pub const MockConnection = struct {
    allocator: std.mem.Allocator,
    responses: std.ArrayList(MockResponse),
    next_id: std.atomic.Value(u64),
    sent_commands: std.ArrayList([]const u8), // Track what was sent

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .responses = std.ArrayList(MockResponse).init(allocator),
            .next_id = std.atomic.Value(u64).init(1),
            .sent_commands = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.responses.items) |resp| {
            self.allocator.free(resp.method);
            self.allocator.free(resp.response_json);
        }
        self.responses.deinit();
        for (self.sent_commands.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.sent_commands.deinit();
    }

    /// Queue a response for a specific method
    pub fn queueResponse(self: *Self, method: []const u8, response_json: []const u8) !void {
        try self.responses.append(.{
            .method = try self.allocator.dupe(u8, method),
            .response_json = try self.allocator.dupe(u8, response_json),
        });
    }

    /// Simulate sending a command and receiving a response
    pub fn sendCommand(
        self: *Self,
        method: []const u8,
        params: anytype,
        session_id: ?[]const u8,
    ) !std.json.Value {
        _ = params;
        _ = session_id;

        // Track what was sent
        try self.sent_commands.append(try self.allocator.dupe(u8, method));

        // Find queued response for this method
        for (self.responses.items, 0..) |resp, i| {
            if (std.mem.eql(u8, resp.method, method)) {
                // Remove and return this response
                const queued = self.responses.orderedRemove(i);
                defer {
                    self.allocator.free(queued.method);
                    self.allocator.free(queued.response_json);
                }

                // Parse the response JSON
                const parsed = try std.json.parseFromSlice(
                    std.json.Value,
                    self.allocator,
                    queued.response_json,
                    .{},
                );
                defer parsed.deinit();

                // Return a copy of the value
                return try cloneJsonValue(self.allocator, parsed.value);
            }
        }

        // No queued response - return empty result
        return .{ .object = std.json.ObjectMap.init(self.allocator) };
    }

    /// Get the next command ID
    pub fn nextId(self: *Self) u64 {
        return self.next_id.fetchAdd(1, .monotonic);
    }

    /// Check if a command was sent
    pub fn wasCommandSent(self: *Self, method: []const u8) bool {
        for (self.sent_commands.items) |cmd| {
            if (std.mem.eql(u8, cmd, method)) return true;
        }
        return false;
    }

    /// Clear sent commands history
    pub fn clearSentCommands(self: *Self) void {
        for (self.sent_commands.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.sent_commands.clearRetainingCapacity();
    }
};

/// Clone a JSON value (deep copy)
fn cloneJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .number_string => |s| .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| blk: {
            var new_arr = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try new_arr.append(try cloneJsonValue(allocator, item));
            }
            break :blk .{ .array = new_arr };
        },
        .object => |obj| blk: {
            var new_obj = std.json.ObjectMap.init(allocator);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                try new_obj.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try cloneJsonValue(allocator, entry.value_ptr.*),
                );
            }
            break :blk .{ .object = new_obj };
        },
    };
}

// ─── MockConnection Tests ─────────────────────────────────────────────────────

test "MockConnection - init and deinit" {
    var mock = MockConnection.init(std.testing.allocator);
    mock.deinit();
}

test "MockConnection - queueResponse and sendCommand" {
    var mock = MockConnection.init(std.testing.allocator);
    defer mock.deinit();

    try mock.queueResponse("Page.navigate", "{\"frameId\":\"F1\"}");

    const result = try mock.sendCommand("Page.navigate", .{}, null);

    try std.testing.expect(result.object.get("frameId") != null);
}

test "MockConnection - tracks sent commands" {
    var mock = MockConnection.init(std.testing.allocator);
    defer mock.deinit();

    try mock.queueResponse("Page.enable", "{}");
    try mock.queueResponse("Page.navigate", "{\"frameId\":\"F1\"}");

    try std.testing.expect(!mock.wasCommandSent("Page.enable"));

    _ = try mock.sendCommand("Page.enable", .{}, null);
    try std.testing.expect(mock.wasCommandSent("Page.enable"));

    _ = try mock.sendCommand("Page.navigate", .{ .url = "https://example.com" }, null);
    try std.testing.expect(mock.wasCommandSent("Page.navigate"));
}

test "MockConnection - returns empty object for unqueued method" {
    var mock = MockConnection.init(std.testing.allocator);
    defer mock.deinit();

    const result = try mock.sendCommand("Unknown.method", .{}, null);

    try std.testing.expect(result == .object);
    try std.testing.expectEqual(@as(usize, 0), result.object.count());
}

test "MockConnection - nextId is monotonic" {
    var mock = MockConnection.init(std.testing.allocator);
    defer mock.deinit();

    const id1 = mock.nextId();
    const id2 = mock.nextId();
    const id3 = mock.nextId();

    try std.testing.expectEqual(@as(u64, 1), id1);
    try std.testing.expectEqual(@as(u64, 2), id2);
    try std.testing.expectEqual(@as(u64, 3), id3);
}

test "MockConnection - clearSentCommands" {
    var mock = MockConnection.init(std.testing.allocator);
    defer mock.deinit();

    try mock.queueResponse("Test.method", "{}");
    _ = try mock.sendCommand("Test.method", .{}, null);

    try std.testing.expect(mock.wasCommandSent("Test.method"));

    mock.clearSentCommands();

    try std.testing.expect(!mock.wasCommandSent("Test.method"));
}

test "MockConnection - complex response" {
    var mock = MockConnection.init(std.testing.allocator);
    defer mock.deinit();

    const response_json =
        \\{
        \\  "targetInfos": [
        \\    {"targetId":"T1","type":"page","title":"Page","url":"https://example.com","attached":true}
        \\  ]
        \\}
    ;
    try mock.queueResponse("Target.getTargets", response_json);

    const result = try mock.sendCommand("Target.getTargets", .{}, null);

    const target_infos = result.object.get("targetInfos");
    try std.testing.expect(target_infos != null);
    try std.testing.expectEqual(@as(usize, 1), target_infos.?.array.items.len);
}

test "MockConnection - multiple responses for same method" {
    var mock = MockConnection.init(std.testing.allocator);
    defer mock.deinit();

    try mock.queueResponse("Page.navigate", "{\"frameId\":\"F1\"}");
    try mock.queueResponse("Page.navigate", "{\"frameId\":\"F2\"}");

    const result1 = try mock.sendCommand("Page.navigate", .{}, null);
    const result2 = try mock.sendCommand("Page.navigate", .{}, null);

    try std.testing.expectEqualStrings("F1", result1.object.get("frameId").?.string);
    try std.testing.expectEqualStrings("F2", result2.object.get("frameId").?.string);
}
