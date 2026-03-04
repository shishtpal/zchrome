const std = @import("std");
const json = @import("json");
const Session = @import("../core/session.zig").Session;
const Event = @import("../core/protocol.zig").Event;

/// Runtime domain client
pub const Runtime = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable runtime domain
    pub fn enable(self: *Self) !void {
        _ = try self.session.sendCommand("Runtime.enable", .{});
    }

    /// Disable runtime domain
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("Runtime.disable", .{});
    }

    /// Evaluate JavaScript expression
    pub fn evaluate(self: *Self, allocator: std.mem.Allocator, expression: []const u8, opts: EvaluateOptions) !RemoteObject {
        const result = try self.session.sendCommand("Runtime.evaluate", .{
            .expression = expression,
            .object_group = opts.object_group,
            .include_command_line_api = opts.include_command_line_api,
            .silent = opts.silent,
            .context_id = opts.context_id,
            .return_by_value = opts.return_by_value,
            .await_promise = opts.await_promise,
            .user_gesture = opts.user_gesture,
        });

        const result_obj = result.get("result") orelse return error.MissingField;
        return try parseRemoteObject(allocator, result_obj);
    }

    /// Call a function on an object
    pub fn callFunctionOn(
        self: *Self,
        allocator: std.mem.Allocator,
        function_declaration: []const u8,
        object_id: ?[]const u8,
        arguments: ?[]const CallArgument,
        opts: CallFunctionOptions,
    ) !RemoteObject {
        const result = try self.session.sendCommand("Runtime.callFunctionOn", .{
            .function_declaration = function_declaration,
            .object_id = object_id,
            .arguments = arguments,
            .return_by_value = opts.return_by_value,
            .await_promise = opts.await_promise,
            .execution_context_id = opts.execution_context_id,
        });

        const result_obj = result.get("result") orelse return error.MissingField;
        return try parseRemoteObject(allocator, result_obj);
    }

    /// Get properties of an object
    pub fn getProperties(self: *Self, allocator: std.mem.Allocator, object_id: []const u8, own_properties: ?bool) ![]PropertyDescriptor {
        const result = try self.session.sendCommand("Runtime.getProperties", .{
            .object_id = object_id,
            .own_properties = own_properties,
        });

        const props = try result.getArray("result");
        var properties = std.ArrayList(PropertyDescriptor).init(allocator);
        errdefer properties.deinit();

        for (props) |prop| {
            try properties.append(try parsePropertyDescriptor(allocator, prop));
        }

        return properties.toOwnedSlice();
    }

    /// Release a remote object
    pub fn releaseObject(self: *Self, object_id: []const u8) !void {
        _ = try self.session.sendCommand("Runtime.releaseObject", .{
            .object_id = object_id,
        });
    }

    /// Release all objects in an object group
    pub fn releaseObjectGroup(self: *Self, object_group: []const u8) !void {
        _ = try self.session.sendCommand("Runtime.releaseObjectGroup", .{
            .object_group = object_group,
        });
    }

    /// Discard collected console entries
    pub fn discardConsoleEntries(self: *Self) !void {
        _ = try self.session.sendCommand("Runtime.discardConsoleEntries", .{});
    }

    /// Run garbage collection
    pub fn runIfWaitingForDebugger(self: *Self) !void {
        _ = try self.session.sendCommand("Runtime.runIfWaitingForDebugger", .{});
    }

    /// Set custom object formatter enabled
    pub fn setCustomObjectFormatterEnabled(self: *Self, enabled: bool) !void {
        _ = try self.session.sendCommand("Runtime.setCustomObjectFormatterEnabled", .{
            .enabled = enabled,
        });
    }

    /// Await a promise
    pub fn awaitPromise(self: *Self, allocator: std.mem.Allocator, promise_object_id: []const u8) !RemoteObject {
        const result = try self.session.sendCommand("Runtime.awaitPromise", .{
            .promise_object_id = promise_object_id,
            .return_by_value = true,
        });

        const result_obj = result.get("result") orelse return error.MissingField;
        return try parseRemoteObject(allocator, result_obj);
    }

    /// Evaluate expression and return as value
    pub fn evaluateAs(self: *Self, comptime T: type, expression: []const u8) !T {
        const result = try self.session.sendCommand("Runtime.evaluate", .{
            .expression = expression,
            .return_by_value = true,
        });

        const result_obj = result.get("result") orelse return error.MissingField;
        const value = result_obj.get("value") orelse return error.MissingField;

        return switch (@typeInfo(T)) {
            .int => @intCast(switch (value) {
                .integer => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => return error.TypeMismatch,
            }),
            .float => @floatCast(switch (value) {
                .float => |f| f,
                .integer => |i| @as(f64, @floatFromInt(i)),
                else => return error.TypeMismatch,
            }),
            .bool => switch (value) {
                .bool => |b| b,
                else => return error.TypeMismatch,
            },
            .pointer => |ptr| {
                if (ptr.size == .slice and ptr.child == u8) {
                    return switch (value) {
                        .string => |s| s,
                        else => return error.TypeMismatch,
                    };
                }
                return error.TypeMismatch;
            },
            else => return error.TypeMismatch,
        };
    }
};

/// Options for Runtime.evaluate
pub const EvaluateOptions = struct {
    object_group: ?[]const u8 = null,
    include_command_line_api: ?bool = null,
    silent: ?bool = null,
    context_id: ?i64 = null,
    return_by_value: ?bool = null,
    await_promise: ?bool = null,
    user_gesture: ?bool = null,
};

/// Options for Runtime.callFunctionOn
pub const CallFunctionOptions = struct {
    return_by_value: ?bool = null,
    await_promise: ?bool = null,
    execution_context_id: ?i64 = null,
};

/// Remote object representation
pub const RemoteObject = struct {
    type: []const u8,
    subtype: ?[]const u8 = null,
    class_name: ?[]const u8 = null,
    value: ?json.Value = null,
    description: ?[]const u8 = null,
    object_id: ?[]const u8 = null,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        if (self.subtype) |s| allocator.free(s);
        if (self.class_name) |c| allocator.free(c);
        if (self.description) |d| allocator.free(d);
        if (self.object_id) |o| allocator.free(o);
    }

    /// Check if this is a primitive value
    pub fn isPrimitive(self: *const Self) bool {
        return std.mem.eql(u8, self.type, "number") or
            std.mem.eql(u8, self.type, "string") or
            std.mem.eql(u8, self.type, "boolean") or
            std.mem.eql(u8, self.type, "undefined") or
            std.mem.eql(u8, self.type, "null");
    }

    /// Get value as string
    pub fn asString(self: *const Self) ?[]const u8 {
        if (self.value) |v| {
            return switch (v) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    /// Get value as number
    pub fn asNumber(self: *const Self) ?f64 {
        if (self.value) |v| {
            return switch (v) {
                .float => |f| f,
                .integer => |i| @floatFromInt(i),
                else => null,
            };
        }
        return null;
    }

    /// Get value as boolean
    pub fn asBool(self: *const Self) ?bool {
        if (self.value) |v| {
            return switch (v) {
                .bool => |b| b,
                else => null,
            };
        }
        return null;
    }
};

/// Call argument
pub const CallArgument = struct {
    value: ?json.Value = null,
    unserializable_value: ?[]const u8 = null,
    object_id: ?[]const u8 = null,
};

/// Property descriptor
pub const PropertyDescriptor = struct {
    name: []const u8,
    value: ?RemoteObject = null,
    writable: ?bool = null,
    get: ?RemoteObject = null,
    set: ?RemoteObject = null,
    configurable: ?bool = null,
    enumerable: ?bool = null,
    symbol: ?RemoteObject = null,

    pub fn deinit(self: *PropertyDescriptor, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.value) |*v| v.deinit(allocator);
        if (self.get) |*g| g.deinit(allocator);
        if (self.set) |*s| s.deinit(allocator);
        if (self.symbol) |*sym| sym.deinit(allocator);
    }
};

/// Parse a remote object from JSON
fn parseRemoteObject(allocator: std.mem.Allocator, obj: json.Value) !RemoteObject {
    return .{
        .type = try allocator.dupe(u8, try obj.getString("type")),
        .subtype = if (obj.get("subtype")) |v| switch (v) {
            .string => |s| try allocator.dupe(u8, s),
            else => null,
        } else null,
        .class_name = if (obj.get("className")) |v| switch (v) {
            .string => |s| try allocator.dupe(u8, s),
            else => null,
        } else null,
        .value = obj.get("value"),
        .description = if (obj.get("description")) |v| switch (v) {
            .string => |s| try allocator.dupe(u8, s),
            else => null,
        } else null,
        .object_id = if (obj.get("objectId")) |v| switch (v) {
            .string => |s| try allocator.dupe(u8, s),
            else => null,
        } else null,
    };
}

/// Parse a property descriptor from JSON
fn parsePropertyDescriptor(allocator: std.mem.Allocator, obj: json.Value) !PropertyDescriptor {
    return .{
        .name = try allocator.dupe(u8, try obj.getString("name")),
        .value = if (obj.get("value")) |v|
            try parseRemoteObject(allocator, v)
        else
            null,
        .writable = if (obj.get("writable")) |v| switch (v) { .bool => |b| b, else => null } else null,
        .get = if (obj.get("get")) |v|
            try parseRemoteObject(allocator, v)
        else
            null,
        .set = if (obj.get("set")) |v|
            try parseRemoteObject(allocator, v)
        else
            null,
        .configurable = if (obj.get("configurable")) |v| switch (v) { .bool => |b| b, else => null } else null,
        .enumerable = if (obj.get("enumerable")) |v| switch (v) { .bool => |b| b, else => null } else null,
        .symbol = if (obj.get("symbol")) |v|
            try parseRemoteObject(allocator, v)
        else
            null,
    };
}

// ─── Event Types ────────────────────────────────────────────────────────────

pub const ConsoleAPICalled = struct {
    type: []const u8,
    args: []RemoteObject,
    execution_context_id: i64,
    timestamp: f64,
    stack_trace: ?StackTrace = null,
};

pub const ExceptionThrown = struct {
    timestamp: f64,
    exception_details: ExceptionDetails,
};

pub const ExceptionDetails = struct {
    exception_id: i64,
    text: []const u8,
    line_number: i32,
    column_number: i32,
    script_id: ?[]const u8 = null,
    url: ?[]const u8 = null,
    exception: ?RemoteObject = null,
};

pub const ExecutionContextCreated = struct {
    context: ExecutionContextDescription,
};

pub const ExecutionContextDestroyed = struct {
    execution_context_id: i64,
};

pub const ExecutionContextDescription = struct {
    id: i64,
    origin: []const u8,
    name: []const u8,
    aux_data: ?json.Value = null,
};

pub const StackTrace = struct {
    call_frames: []CallFrame,
};

pub const CallFrame = struct {
    function_name: []const u8,
    script_id: []const u8,
    url: []const u8,
    line_number: i32,
    column_number: i32,
};
