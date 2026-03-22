const std = @import("std");
const json = @import("json");
const Session = @import("../core/session.zig").Session;
const RemoteObject = @import("runtime.zig").RemoteObject;

// ─── Types ──────────────────────────────────────────────────────────────────

/// Breakpoint identifier
pub const BreakpointId = []const u8;

/// Call frame identifier
pub const CallFrameId = []const u8;

/// Script identifier
pub const ScriptId = []const u8;

/// Location in source code
pub const Location = struct {
    script_id: ScriptId,
    line_number: i64,
    column_number: ?i64 = null,

    pub fn deinit(self: *Location, allocator: std.mem.Allocator) void {
        allocator.free(self.script_id);
    }
};

/// Script position
pub const ScriptPosition = struct {
    line_number: i64,
    column_number: i64,
};

/// Scope type
pub const ScopeType = enum {
    global,
    local,
    with,
    closure,
    catch_scope,
    block,
    script,
    eval,
    module,
    wasm_expression_stack,

    pub fn fromString(s: []const u8) ScopeType {
        const map = std.StaticStringMap(ScopeType).initComptime(.{
            .{ "global", .global },
            .{ "local", .local },
            .{ "with", .with },
            .{ "closure", .closure },
            .{ "catch", .catch_scope },
            .{ "block", .block },
            .{ "script", .script },
            .{ "eval", .eval },
            .{ "module", .module },
            .{ "wasm-expression-stack", .wasm_expression_stack },
        });
        return map.get(s) orelse .local;
    }
};

/// Scope information
pub const Scope = struct {
    scope_type: ScopeType,
    object: json.Value, // RemoteObject
    name: ?[]const u8 = null,
    start_location: ?Location = null,
    end_location: ?Location = null,

    pub fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
        self.object.deinit(allocator);
        if (self.name) |n| allocator.free(n);
        if (self.start_location) |*loc| loc.deinit(allocator);
        if (self.end_location) |*loc| loc.deinit(allocator);
    }
};

/// Call frame during debugging
pub const CallFrame = struct {
    call_frame_id: CallFrameId,
    function_name: []const u8,
    function_location: ?Location = null,
    location: Location,
    url: []const u8,
    scope_chain: []Scope,
    this: json.Value, // RemoteObject
    return_value: ?json.Value = null, // RemoteObject

    pub fn deinit(self: *CallFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.call_frame_id);
        allocator.free(self.function_name);
        if (self.function_location) |*loc| loc.deinit(allocator);
        self.location.deinit(allocator);
        allocator.free(self.url);
        for (self.scope_chain) |*scope| scope.deinit(allocator);
        allocator.free(self.scope_chain);
        self.this.deinit(allocator);
        if (self.return_value) |*rv| rv.deinit(allocator);
    }
};

/// Reason for pausing execution
pub const PausedReason = enum {
    ambiguous,
    assert,
    csp_violation,
    debug_command,
    dom,
    event_listener,
    exception,
    instrumentation,
    oom,
    other,
    promise_rejection,
    xhr,
    step,

    pub fn fromString(s: []const u8) PausedReason {
        const map = std.StaticStringMap(PausedReason).initComptime(.{
            .{ "ambiguous", .ambiguous },
            .{ "assert", .assert },
            .{ "CSPViolation", .csp_violation },
            .{ "debugCommand", .debug_command },
            .{ "DOM", .dom },
            .{ "EventListener", .event_listener },
            .{ "exception", .exception },
            .{ "instrumentation", .instrumentation },
            .{ "OOM", .oom },
            .{ "other", .other },
            .{ "promiseRejection", .promise_rejection },
            .{ "XHR", .xhr },
            .{ "step", .step },
        });
        return map.get(s) orelse .other;
    }
};

/// Pause on exceptions state
pub const PauseOnExceptionsState = enum {
    none,
    uncaught,
    all,

    pub fn toString(self: PauseOnExceptionsState) []const u8 {
        return switch (self) {
            .none => "none",
            .uncaught => "uncaught",
            .all => "all",
        };
    }
};

/// Breakpoint location
pub const BreakLocation = struct {
    script_id: ScriptId,
    line_number: i64,
    column_number: ?i64 = null,
    break_type: ?[]const u8 = null,

    pub fn deinit(self: *BreakLocation, allocator: std.mem.Allocator) void {
        allocator.free(self.script_id);
        if (self.break_type) |t| allocator.free(t);
    }
};

// ─── Debugger Domain Client ─────────────────────────────────────────────────

/// Debugger domain client for JavaScript debugging
pub const Debugger = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable debugger domain
    pub fn enable(self: *Self) !i64 {
        var result = try self.session.sendCommand("Debugger.enable", .{});
        defer result.deinit(self.session.allocator);

        // Returns debugger ID
        if (result.get("debuggerId")) |v| {
            _ = v; // debuggerId is a string, but we return protocol version
        }
        return 1; // Protocol version
    }

    /// Disable debugger domain
    pub fn disable(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Debugger.disable", .{});
    }

    /// Pause execution
    pub fn pause(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Debugger.pause", .{});
    }

    /// Resume execution
    pub fn @"resume"(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Debugger.resume", .{});
    }

    /// Step over next statement
    pub fn stepOver(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Debugger.stepOver", .{});
    }

    /// Step into function call
    pub fn stepInto(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Debugger.stepInto", .{});
    }

    /// Step out of current function
    pub fn stepOut(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Debugger.stepOut", .{});
    }

    /// Set breakpoint at location
    pub fn setBreakpoint(self: *Self, allocator: std.mem.Allocator, location: Location, condition: ?[]const u8) !struct { breakpoint_id: BreakpointId, actual_location: Location } {
        var result = try self.session.sendCommand("Debugger.setBreakpoint", .{
            .location = .{
                .scriptId = location.script_id,
                .lineNumber = location.line_number,
                .columnNumber = location.column_number,
            },
            .condition = condition,
        });
        defer result.deinit(self.session.allocator);

        const bp_id = try allocator.dupe(u8, try result.getString("breakpointId"));
        errdefer allocator.free(bp_id);

        const actual_loc = result.get("actualLocation") orelse return error.MissingField;
        const actual_location = Location{
            .script_id = try allocator.dupe(u8, try actual_loc.getString("scriptId")),
            .line_number = blk: {
                const line_val = actual_loc.get("lineNumber") orelse return error.MissingField;
                break :blk switch (line_val) {
                    .integer => |i| i,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => return error.TypeMismatch,
                };
            },
            .column_number = if (actual_loc.get("columnNumber")) |col| switch (col) {
                .integer => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => null,
            } else null,
        };

        return .{
            .breakpoint_id = bp_id,
            .actual_location = actual_location,
        };
    }

    /// Set breakpoint by URL (can match multiple scripts)
    pub fn setBreakpointByUrl(
        self: *Self,
        allocator: std.mem.Allocator,
        line_number: i64,
        url: ?[]const u8,
        url_regex: ?[]const u8,
        script_hash: ?[]const u8,
        column_number: ?i64,
        condition: ?[]const u8,
    ) !struct { breakpoint_id: BreakpointId, locations: []Location } {
        var result = try self.session.sendCommand("Debugger.setBreakpointByUrl", .{
            .lineNumber = line_number,
            .url = url,
            .urlRegex = url_regex,
            .scriptHash = script_hash,
            .columnNumber = column_number,
            .condition = condition,
        });
        defer result.deinit(self.session.allocator);

        const bp_id = try allocator.dupe(u8, try result.getString("breakpointId"));
        errdefer allocator.free(bp_id);

        const locs_val = result.get("locations") orelse return error.MissingField;
        const locs_arr = locs_val.asArray() orelse return error.TypeMismatch;

        var locations = try allocator.alloc(Location, locs_arr.len);
        errdefer allocator.free(locations);

        for (locs_arr, 0..) |loc, i| {
            locations[i] = .{
                .script_id = try allocator.dupe(u8, try loc.getString("scriptId")),
                .line_number = blk: {
                    const line_val = loc.get("lineNumber") orelse return error.MissingField;
                    break :blk switch (line_val) {
                        .integer => |i_val| i_val,
                        .float => |f| @as(i64, @intFromFloat(f)),
                        else => return error.TypeMismatch,
                    };
                },
                .column_number = if (loc.get("columnNumber")) |col| switch (col) {
                    .integer => |i_val| i_val,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => null,
                } else null,
            };
        }

        return .{
            .breakpoint_id = bp_id,
            .locations = locations,
        };
    }

    /// Remove breakpoint
    pub fn removeBreakpoint(self: *Self, breakpoint_id: BreakpointId) !void {
        try self.session.sendCommandIgnoreResult("Debugger.removeBreakpoint", .{
            .breakpointId = breakpoint_id,
        });
    }

    /// Evaluate expression on call frame (when paused)
    pub fn evaluateOnCallFrame(
        self: *Self,
        call_frame_id: CallFrameId,
        expression: []const u8,
        object_group: ?[]const u8,
        include_command_line_api: ?bool,
        silent: ?bool,
        return_by_value: ?bool,
        generate_preview: ?bool,
        throw_on_side_effect: ?bool,
    ) !json.Value {
        return try self.session.sendCommand("Debugger.evaluateOnCallFrame", .{
            .callFrameId = call_frame_id,
            .expression = expression,
            .objectGroup = object_group,
            .includeCommandLineAPI = include_command_line_api,
            .silent = silent,
            .returnByValue = return_by_value,
            .generatePreview = generate_preview,
            .throwOnSideEffect = throw_on_side_effect,
        });
    }

    /// Enable or disable all breakpoints
    pub fn setBreakpointsActive(self: *Self, active: bool) !void {
        try self.session.sendCommandIgnoreResult("Debugger.setBreakpointsActive", .{
            .active = active,
        });
    }

    /// Set pause on exceptions state
    pub fn setPauseOnExceptions(self: *Self, state: PauseOnExceptionsState) !void {
        try self.session.sendCommandIgnoreResult("Debugger.setPauseOnExceptions", .{
            .state = state.toString(),
        });
    }

    /// Get script source
    pub fn getScriptSource(self: *Self, allocator: std.mem.Allocator, script_id: ScriptId) ![]const u8 {
        var result = try self.session.sendCommand("Debugger.getScriptSource", .{
            .scriptId = script_id,
        });
        defer result.deinit(self.session.allocator);

        const source = try result.getString("scriptSource");
        return allocator.dupe(u8, source);
    }

    /// Set skip all pauses
    pub fn setSkipAllPauses(self: *Self, skip: bool) !void {
        try self.session.sendCommandIgnoreResult("Debugger.setSkipAllPauses", .{
            .skip = skip,
        });
    }

    /// Continue to location
    pub fn continueToLocation(self: *Self, location: Location, target_call_frames: ?[]const u8) !void {
        try self.session.sendCommandIgnoreResult("Debugger.continueToLocation", .{
            .location = .{
                .scriptId = location.script_id,
                .lineNumber = location.line_number,
                .columnNumber = location.column_number,
            },
            .targetCallFrames = target_call_frames,
        });
    }

    /// Get possible breakpoints in a range
    pub fn getPossibleBreakpoints(self: *Self, allocator: std.mem.Allocator, start: Location, end: ?Location, restrict_to_function: ?bool) ![]BreakLocation {
        var result = try self.session.sendCommand("Debugger.getPossibleBreakpoints", .{
            .start = .{
                .scriptId = start.script_id,
                .lineNumber = start.line_number,
                .columnNumber = start.column_number,
            },
            .end = if (end) |e| .{
                .scriptId = e.script_id,
                .lineNumber = e.line_number,
                .columnNumber = e.column_number,
            } else null,
            .restrictToFunction = restrict_to_function,
        });
        defer result.deinit(self.session.allocator);

        const locs_val = result.get("locations") orelse return error.MissingField;
        const locs_arr = locs_val.asArray() orelse return error.TypeMismatch;

        var locations = try allocator.alloc(BreakLocation, locs_arr.len);
        errdefer allocator.free(locations);

        for (locs_arr, 0..) |loc, i| {
            locations[i] = .{
                .script_id = try allocator.dupe(u8, try loc.getString("scriptId")),
                .line_number = blk: {
                    const line_val = loc.get("lineNumber") orelse return error.MissingField;
                    break :blk switch (line_val) {
                        .integer => |i_val| i_val,
                        .float => |f| @as(i64, @intFromFloat(f)),
                        else => return error.TypeMismatch,
                    };
                },
                .column_number = if (loc.get("columnNumber")) |col| switch (col) {
                    .integer => |i_val| i_val,
                    .float => |f| @as(i64, @intFromFloat(f)),
                    else => null,
                } else null,
                .break_type = if (loc.get("type")) |t| try allocator.dupe(u8, t.string) else null,
            };
        }

        return locations;
    }

    /// Set async call stack depth
    pub fn setAsyncCallStackDepth(self: *Self, max_depth: i64) !void {
        try self.session.sendCommandIgnoreResult("Debugger.setAsyncCallStackDepth", .{
            .maxDepth = max_depth,
        });
    }

    /// Set blackbox patterns (files matching patterns will be skipped during debugging)
    pub fn setBlackboxPatterns(self: *Self, patterns: []const []const u8) !void {
        try self.session.sendCommandIgnoreResult("Debugger.setBlackboxPatterns", .{
            .patterns = patterns,
        });
    }
};

// ─── Event Types ────────────────────────────────────────────────────────────

/// Fired when execution is paused
pub const PausedEvent = struct {
    call_frames: []CallFrame,
    reason: PausedReason,
    data: ?json.Value = null,
    hit_breakpoints: ?[][]const u8 = null,
    async_stack_trace: ?json.Value = null,
    async_stack_trace_id: ?json.Value = null,

    pub fn deinit(self: *PausedEvent, allocator: std.mem.Allocator) void {
        for (self.call_frames) |*cf| cf.deinit(allocator);
        allocator.free(self.call_frames);
        if (self.data) |*d| d.deinit(allocator);
        if (self.hit_breakpoints) |bps| {
            for (bps) |bp| allocator.free(bp);
            allocator.free(bps);
        }
        if (self.async_stack_trace) |*ast| ast.deinit(allocator);
        if (self.async_stack_trace_id) |*asti| asti.deinit(allocator);
    }
};

/// Fired when execution is resumed
pub const ResumedEvent = struct {};

/// Fired when a script is parsed
pub const ScriptParsedEvent = struct {
    script_id: ScriptId,
    url: []const u8,
    start_line: i64,
    start_column: i64,
    end_line: i64,
    end_column: i64,
    execution_context_id: i64,
    hash: []const u8,
    execution_context_aux_data: ?json.Value = null,
    is_live_edit: bool = false,
    source_map_url: ?[]const u8 = null,
    has_source_url: bool = false,
    is_module: bool = false,
    length: ?i64 = null,
    stack_trace: ?json.Value = null,

    pub fn deinit(self: *ScriptParsedEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.script_id);
        allocator.free(self.url);
        allocator.free(self.hash);
        if (self.execution_context_aux_data) |*d| d.deinit(allocator);
        if (self.source_map_url) |url| allocator.free(url);
        if (self.stack_trace) |*st| st.deinit(allocator);
    }
};

/// Fired when script fails to parse
pub const ScriptFailedToParseEvent = struct {
    script_id: ScriptId,
    url: []const u8,
    start_line: i64,
    start_column: i64,
    end_line: i64,
    end_column: i64,
    execution_context_id: i64,
    hash: []const u8,
    execution_context_aux_data: ?json.Value = null,
    source_map_url: ?[]const u8 = null,
    has_source_url: bool = false,
    is_module: bool = false,
    length: ?i64 = null,
    stack_trace: ?json.Value = null,

    pub fn deinit(self: *ScriptFailedToParseEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.script_id);
        allocator.free(self.url);
        allocator.free(self.hash);
        if (self.execution_context_aux_data) |*d| d.deinit(allocator);
        if (self.source_map_url) |url| allocator.free(url);
        if (self.stack_trace) |*st| st.deinit(allocator);
    }
};

/// Fired when breakpoint is resolved
pub const BreakpointResolvedEvent = struct {
    breakpoint_id: BreakpointId,
    location: Location,

    pub fn deinit(self: *BreakpointResolvedEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.breakpoint_id);
        self.location.deinit(allocator);
    }
};
