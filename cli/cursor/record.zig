//! Macro recording functionality.
//!
//! Records browser interactions as reusable, editable macros via WebSocket streaming.

const std = @import("std");
const cdp = @import("cdp");
const macro = @import("macro/mod.zig");
const record_server = @import("record_server.zig");
const utils = @import("utils.zig");

/// Key to Windows virtual key code mapping
pub fn keyToWindowsVirtualKeyCode(key_opt: ?[]const u8, code_opt: ?[]const u8) ?i32 {
    if (code_opt) |code| {
        if (code.len == 4 and std.mem.startsWith(u8, code, "Key")) {
            const c = code[3];
            if (c >= 'A' and c <= 'Z') return @intCast(c);
        }
        if (code.len == 6 and std.mem.startsWith(u8, code, "Digit")) {
            const c = code[5];
            if (c >= '0' and c <= '9') return @intCast(c);
        }

        const code_map = std.StaticStringMap(i32).initComptime(.{
            .{ "Space", 0x20 },
            .{ "Enter", 0x0D },
            .{ "Tab", 0x09 },
            .{ "Backspace", 0x08 },
            .{ "Escape", 0x1B },
            .{ "ArrowUp", 0x26 },
            .{ "ArrowDown", 0x28 },
            .{ "ArrowLeft", 0x25 },
            .{ "ArrowRight", 0x27 },
            .{ "Home", 0x24 },
            .{ "End", 0x23 },
            .{ "PageUp", 0x21 },
            .{ "PageDown", 0x22 },
            .{ "Delete", 0x2E },
            .{ "Insert", 0x2D },
        });
        if (code_map.get(code)) |vk| return vk;
    }

    if (key_opt) |key| {
        if (key.len == 1) {
            const c = key[0];
            if (c >= 'a' and c <= 'z') return @intCast(std.ascii.toUpper(c));
            if (c >= 'A' and c <= 'Z') return @intCast(c);
            if (c >= '0' and c <= '9') return @intCast(c);
        }

        const key_map = std.StaticStringMap(i32).initComptime(.{
            .{ "Control", 0x11 },
            .{ "Shift", 0x10 },
            .{ "Alt", 0x12 },
            .{ "Meta", 0x5B },
        });
        if (key_map.get(key)) |vk| return vk;
    }

    return null;
}

/// Record mouse and keyboard events to a macro file via WebSocket streaming.
/// Events are streamed in real-time and survive page reloads.
pub fn cursorRecord(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: cursor record <filename.json>\n", .{});
        return;
    }

    const filename = args[0];
    const port = record_server.DEFAULT_PORT;

    std.debug.print("Recording on port {}... Press Enter to stop.\n", .{port});

    // Initialize recording
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Get recording JS
    const recording_js = try record_server.getRecordingJs(allocator, port);
    defer allocator.free(recording_js);

    // Inject recording script
    var init_result = try runtime.evaluate(allocator, recording_js, .{ .return_by_value = true });
    defer init_result.deinit(allocator);

    // Inject on page navigation
    var page = cdp.Page.init(session);
    try page.enable();
    _ = try page.addScriptToEvaluateOnNewDocument(recording_js);

    // Start recording server and wait for stop
    var server = try record_server.RecordServer.init(allocator, io, port);
    defer server.deinit();

    // Wait for user to press Enter
    utils.waitForEnter(io);

    // Stop and save
    var stop_result = runtime.evaluate(allocator,
        \\(function() {
        \\  if (window.__zchrome_stop_recording) window.__zchrome_stop_recording();
        \\})()
    , .{}) catch null;
    if (stop_result) |*r| r.deinit(allocator);

    // Stop recording and get commands from server
    const commands = server.stop();

    if (commands.len == 0) {
        std.debug.print("No commands recorded.\n", .{});
        return;
    }

    // Save to file
    const macro_data = macro.CommandMacro{
        .version = 2,
        .commands = commands,
    };
    try macro.saveCommandMacro(allocator, io, filename, &macro_data);
    std.debug.print("Recorded {} commands to {s}\n", .{ commands.len, filename });
}
