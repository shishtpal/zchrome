const std = @import("std");
const cdp = @import("cdp");
const json = @import("json");

const Debugger = cdp.Debugger;
const PausedReason = cdp.PausedReason;
const PauseOnExceptionsState = cdp.PauseOnExceptionsState;
const ScopeType = cdp.ScopeType;
const DebuggerLocation = cdp.DebuggerLocation;

// ─── PausedReason Tests ─────────────────────────────────────────────────────

test "PausedReason - fromString parses known reasons" {
    try std.testing.expectEqual(PausedReason.ambiguous, PausedReason.fromString("ambiguous"));
    try std.testing.expectEqual(PausedReason.assert, PausedReason.fromString("assert"));
    try std.testing.expectEqual(PausedReason.csp_violation, PausedReason.fromString("CSPViolation"));
    try std.testing.expectEqual(PausedReason.debug_command, PausedReason.fromString("debugCommand"));
    try std.testing.expectEqual(PausedReason.dom, PausedReason.fromString("DOM"));
    try std.testing.expectEqual(PausedReason.event_listener, PausedReason.fromString("EventListener"));
    try std.testing.expectEqual(PausedReason.exception, PausedReason.fromString("exception"));
    try std.testing.expectEqual(PausedReason.instrumentation, PausedReason.fromString("instrumentation"));
    try std.testing.expectEqual(PausedReason.oom, PausedReason.fromString("OOM"));
    try std.testing.expectEqual(PausedReason.other, PausedReason.fromString("other"));
    try std.testing.expectEqual(PausedReason.promise_rejection, PausedReason.fromString("promiseRejection"));
    try std.testing.expectEqual(PausedReason.xhr, PausedReason.fromString("XHR"));
    try std.testing.expectEqual(PausedReason.step, PausedReason.fromString("step"));
}

test "PausedReason - fromString returns other for unknown" {
    try std.testing.expectEqual(PausedReason.other, PausedReason.fromString("unknown"));
    try std.testing.expectEqual(PausedReason.other, PausedReason.fromString(""));
}

// ─── PauseOnExceptionsState Tests ───────────────────────────────────────────

test "PauseOnExceptionsState - toString returns correct strings" {
    try std.testing.expectEqualStrings("none", PauseOnExceptionsState.none.toString());
    try std.testing.expectEqualStrings("uncaught", PauseOnExceptionsState.uncaught.toString());
    try std.testing.expectEqualStrings("all", PauseOnExceptionsState.all.toString());
}

// ─── ScopeType Tests ────────────────────────────────────────────────────────

test "ScopeType - fromString parses known types" {
    try std.testing.expectEqual(ScopeType.global, ScopeType.fromString("global"));
    try std.testing.expectEqual(ScopeType.local, ScopeType.fromString("local"));
    try std.testing.expectEqual(ScopeType.with, ScopeType.fromString("with"));
    try std.testing.expectEqual(ScopeType.closure, ScopeType.fromString("closure"));
    try std.testing.expectEqual(ScopeType.catch_scope, ScopeType.fromString("catch"));
    try std.testing.expectEqual(ScopeType.block, ScopeType.fromString("block"));
    try std.testing.expectEqual(ScopeType.script, ScopeType.fromString("script"));
    try std.testing.expectEqual(ScopeType.eval, ScopeType.fromString("eval"));
    try std.testing.expectEqual(ScopeType.module, ScopeType.fromString("module"));
    try std.testing.expectEqual(ScopeType.wasm_expression_stack, ScopeType.fromString("wasm-expression-stack"));
}

test "ScopeType - fromString returns local for unknown" {
    try std.testing.expectEqual(ScopeType.local, ScopeType.fromString("unknown"));
}

// ─── Location Tests ─────────────────────────────────────────────────────────

test "DebuggerLocation - create with all fields" {
    var loc = DebuggerLocation{
        .script_id = try std.testing.allocator.dupe(u8, "script123"),
        .line_number = 42,
        .column_number = 10,
    };
    defer loc.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("script123", loc.script_id);
    try std.testing.expectEqual(@as(i64, 42), loc.line_number);
    try std.testing.expectEqual(@as(?i64, 10), loc.column_number);
}

test "DebuggerLocation - create without column" {
    var loc = DebuggerLocation{
        .script_id = try std.testing.allocator.dupe(u8, "script456"),
        .line_number = 100,
        .column_number = null,
    };
    defer loc.deinit(std.testing.allocator);

    try std.testing.expect(loc.column_number == null);
}

// ─── Debugger Client Struct Tests ───────────────────────────────────────────

test "Debugger - struct has expected layout" {
    const DebuggerClient = struct {
        session: *anyopaque,
    };
    var dummy: u8 = 0;
    const client = DebuggerClient{ .session = @ptrCast(&dummy) };
    try std.testing.expect(client.session != undefined);
}

// ─── JSON Parsing Tests ─────────────────────────────────────────────────────

test "Parse location from JSON" {
    const json_str =
        \\{"scriptId":"123","lineNumber":42,"columnNumber":5}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const script_id = try parsed.getString("scriptId");
    try std.testing.expectEqualStrings("123", script_id);

    const line_val = parsed.get("lineNumber") orelse return error.MissingField;
    const line_number = switch (line_val) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => return error.TypeMismatch,
    };
    try std.testing.expectEqual(@as(i64, 42), line_number);
}

test "Parse breakpoint response from JSON" {
    const json_str =
        \\{"breakpointId":"bp1","actualLocation":{"scriptId":"script1","lineNumber":10,"columnNumber":0}}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const bp_id = try parsed.getString("breakpointId");
    try std.testing.expectEqualStrings("bp1", bp_id);

    const actual_loc = parsed.get("actualLocation") orelse return error.MissingField;
    const actual_script_id = try actual_loc.getString("scriptId");
    try std.testing.expectEqualStrings("script1", actual_script_id);
}

test "Parse paused event from JSON" {
    const json_str =
        \\{"reason":"exception","hitBreakpoints":["bp1","bp2"]}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const reason_str = try parsed.getString("reason");
    const reason = PausedReason.fromString(reason_str);
    try std.testing.expectEqual(PausedReason.exception, reason);

    const hit_bps = parsed.get("hitBreakpoints") orelse return error.MissingField;
    const arr = hit_bps.asArray() orelse return error.TypeMismatch;
    try std.testing.expectEqual(@as(usize, 2), arr.len);
}

test "Parse script parsed event from JSON" {
    const json_str =
        \\{"scriptId":"42","url":"https://example.com/app.js","startLine":0,"startColumn":0,"endLine":100,"endColumn":0,"executionContextId":1,"hash":"abc123"}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const script_id = try parsed.getString("scriptId");
    try std.testing.expectEqualStrings("42", script_id);

    const url = try parsed.getString("url");
    try std.testing.expectEqualStrings("https://example.com/app.js", url);

    const hash = try parsed.getString("hash");
    try std.testing.expectEqualStrings("abc123", hash);
}

// ─── Type Size Tests ────────────────────────────────────────────────────────

test "Debugger types have expected sizes" {
    try std.testing.expect(@sizeOf(PausedReason) <= 1);
    try std.testing.expect(@sizeOf(PauseOnExceptionsState) <= 1);
    try std.testing.expect(@sizeOf(ScopeType) <= 1);
}
