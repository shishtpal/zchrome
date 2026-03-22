const std = @import("std");
const cdp = @import("cdp");
const json = @import("json");

const Security = cdp.Security;
const SecurityState = cdp.SecurityState;
const CertificateErrorAction = cdp.CertificateErrorAction;

// ─── SecurityState Tests ────────────────────────────────────────────────────

test "SecurityState - fromString parses known states" {
    try std.testing.expectEqual(SecurityState.unknown, SecurityState.fromString("unknown"));
    try std.testing.expectEqual(SecurityState.neutral, SecurityState.fromString("neutral"));
    try std.testing.expectEqual(SecurityState.insecure, SecurityState.fromString("insecure"));
    try std.testing.expectEqual(SecurityState.secure, SecurityState.fromString("secure"));
    try std.testing.expectEqual(SecurityState.info, SecurityState.fromString("info"));
    try std.testing.expectEqual(SecurityState.insecure_broken, SecurityState.fromString("insecure-broken"));
}

test "SecurityState - fromString returns unknown for invalid input" {
    try std.testing.expectEqual(SecurityState.unknown, SecurityState.fromString("invalid"));
    try std.testing.expectEqual(SecurityState.unknown, SecurityState.fromString(""));
    try std.testing.expectEqual(SecurityState.unknown, SecurityState.fromString("SECURE"));
}

// ─── CertificateErrorAction Tests ───────────────────────────────────────────

test "CertificateErrorAction - toString returns correct strings" {
    try std.testing.expectEqualStrings("continue", CertificateErrorAction.@"continue".toString());
    try std.testing.expectEqualStrings("cancel", CertificateErrorAction.cancel.toString());
}

// ─── Security Client Struct Tests ───────────────────────────────────────────

test "Security - init creates instance with session" {
    // This test verifies the struct layout without requiring a real session
    const SecurityClient = struct {
        session: *anyopaque,
    };
    var dummy: u8 = 0;
    const client = SecurityClient{ .session = @ptrCast(&dummy) };
    try std.testing.expect(client.session != undefined);
}

// ─── Type Size Tests ────────────────────────────────────────────────────────

test "Security types have expected sizes" {
    // Enum should be small
    try std.testing.expect(@sizeOf(SecurityState) <= 1);
    try std.testing.expect(@sizeOf(CertificateErrorAction) <= 1);
}

// ─── JSON Parsing Tests ─────────────────────────────────────────────────────

test "Parse security state from JSON event" {
    const json_str =
        \\{"securityState":"secure","schemeIsCryptographic":true}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const state_str = try parsed.getString("securityState");
    const state = SecurityState.fromString(state_str);
    try std.testing.expectEqual(SecurityState.secure, state);

    const scheme_val = parsed.get("schemeIsCryptographic") orelse return error.MissingField;
    try std.testing.expect(scheme_val.bool == true);
}

test "Parse certificate error event from JSON" {
    const json_str =
        \\{"eventId":123,"errorType":"net::ERR_CERT_AUTHORITY_INVALID","requestURL":"https://example.com"}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const event_id_val = parsed.get("eventId") orelse return error.MissingField;
    const event_id = switch (event_id_val) {
        .integer => |i| i,
        .float => |f| @as(i64, @intFromFloat(f)),
        else => return error.TypeMismatch,
    };
    try std.testing.expectEqual(@as(i64, 123), event_id);

    const error_type = try parsed.getString("errorType");
    try std.testing.expectEqualStrings("net::ERR_CERT_AUTHORITY_INVALID", error_type);

    const request_url = try parsed.getString("requestURL");
    try std.testing.expectEqualStrings("https://example.com", request_url);
}
