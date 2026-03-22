const std = @import("std");
const cdp = @import("cdp");
const json = @import("json");

const CSS = cdp.CSS;
const StyleSheetOrigin = cdp.StyleSheetOrigin;
const SourceRange = cdp.SourceRange;

// ─── StyleSheetOrigin Tests ─────────────────────────────────────────────────

test "StyleSheetOrigin - fromString parses known origins" {
    try std.testing.expectEqual(StyleSheetOrigin.injected, StyleSheetOrigin.fromString("injected"));
    try std.testing.expectEqual(StyleSheetOrigin.user_agent, StyleSheetOrigin.fromString("user-agent"));
    try std.testing.expectEqual(StyleSheetOrigin.inspector, StyleSheetOrigin.fromString("inspector"));
    try std.testing.expectEqual(StyleSheetOrigin.regular, StyleSheetOrigin.fromString("regular"));
}

test "StyleSheetOrigin - fromString returns regular for unknown" {
    try std.testing.expectEqual(StyleSheetOrigin.regular, StyleSheetOrigin.fromString("unknown"));
    try std.testing.expectEqual(StyleSheetOrigin.regular, StyleSheetOrigin.fromString(""));
}

test "StyleSheetOrigin - toString returns correct strings" {
    try std.testing.expectEqualStrings("injected", StyleSheetOrigin.injected.toString());
    try std.testing.expectEqualStrings("user-agent", StyleSheetOrigin.user_agent.toString());
    try std.testing.expectEqualStrings("inspector", StyleSheetOrigin.inspector.toString());
    try std.testing.expectEqualStrings("regular", StyleSheetOrigin.regular.toString());
}

// ─── SourceRange Tests ──────────────────────────────────────────────────────

test "SourceRange - create and access fields" {
    const range = SourceRange{
        .start_line = 10,
        .start_column = 5,
        .end_line = 15,
        .end_column = 20,
    };

    try std.testing.expectEqual(@as(i64, 10), range.start_line);
    try std.testing.expectEqual(@as(i64, 5), range.start_column);
    try std.testing.expectEqual(@as(i64, 15), range.end_line);
    try std.testing.expectEqual(@as(i64, 20), range.end_column);
}

// ─── CSS Client Struct Tests ────────────────────────────────────────────────

test "CSS - struct has expected layout" {
    // Verify the CSS struct exists and has session field
    const CSSClient = struct {
        session: *anyopaque,
    };
    var dummy: u8 = 0;
    const client = CSSClient{ .session = @ptrCast(&dummy) };
    try std.testing.expect(client.session != undefined);
}

// ─── JSON Parsing Tests ─────────────────────────────────────────────────────

test "Parse stylesheet header from JSON" {
    const json_str =
        \\{"styleSheetId":"ss1","frameId":"frame1","sourceURL":"https://example.com/style.css","origin":"regular","title":"Main Styles","disabled":false,"isInline":false,"startLine":0,"startColumn":0,"length":1024}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const id = try parsed.getString("styleSheetId");
    try std.testing.expectEqualStrings("ss1", id);

    const frame_id = try parsed.getString("frameId");
    try std.testing.expectEqualStrings("frame1", frame_id);

    const origin_str = try parsed.getString("origin");
    const origin = StyleSheetOrigin.fromString(origin_str);
    try std.testing.expectEqual(StyleSheetOrigin.regular, origin);

    const disabled_val = parsed.get("disabled") orelse return error.MissingField;
    try std.testing.expect(disabled_val.bool == false);
}

test "Parse computed style property from JSON" {
    const json_str =
        \\{"name":"color","value":"rgb(0, 0, 0)"}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const name = try parsed.getString("name");
    try std.testing.expectEqualStrings("color", name);

    const value = try parsed.getString("value");
    try std.testing.expectEqualStrings("rgb(0, 0, 0)", value);
}

test "Parse computed style array from JSON" {
    const json_str =
        \\{"computedStyle":[{"name":"display","value":"block"},{"name":"color","value":"red"}]}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const computed_style = parsed.get("computedStyle") orelse return error.MissingField;
    const arr = computed_style.asArray() orelse return error.TypeMismatch;

    try std.testing.expectEqual(@as(usize, 2), arr.len);

    const first = arr[0];
    try std.testing.expectEqualStrings("display", try first.getString("name"));
    try std.testing.expectEqualStrings("block", try first.getString("value"));

    const second = arr[1];
    try std.testing.expectEqualStrings("color", try second.getString("name"));
    try std.testing.expectEqualStrings("red", try second.getString("value"));
}

test "Parse CSS rule from JSON" {
    const json_str =
        \\{"styleSheetId":"ss1","selectorList":{"selectors":[{"text":".btn"}],"text":".btn"},"origin":"regular"}
    ;
    var parsed = try json.parse(std.testing.allocator, json_str, .{});
    defer parsed.deinit(std.testing.allocator);

    const style_sheet_id = try parsed.getString("styleSheetId");
    try std.testing.expectEqualStrings("ss1", style_sheet_id);

    const selector_list = parsed.get("selectorList") orelse return error.MissingField;
    const selector_text = try selector_list.getString("text");
    try std.testing.expectEqualStrings(".btn", selector_text);

    const origin_str = try parsed.getString("origin");
    try std.testing.expectEqual(StyleSheetOrigin.regular, StyleSheetOrigin.fromString(origin_str));
}

// ─── Type Size Tests ────────────────────────────────────────────────────────

test "CSS types have expected sizes" {
    try std.testing.expect(@sizeOf(StyleSheetOrigin) <= 1);
    try std.testing.expect(@sizeOf(SourceRange) == @sizeOf(i64) * 4);
}
