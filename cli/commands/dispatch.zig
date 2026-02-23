//! Command dispatcher for session-level commands.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");
const navigation = @import("navigation.zig");
const capture = @import("capture.zig");
const cookies_cmd = @import("cookies.zig");
const storage_cmd = @import("storage.zig");
const evaluate_cmd = @import("evaluate.zig");
const elements = @import("elements.zig");
const scroll_cmd = @import("scroll.zig");
const drag_cmd = @import("drag.zig");
const upload_cmd = @import("upload.zig");
const keyboard = @import("keyboard.zig");
const mouse_cmd = @import("mouse.zig");
const wait_cmd = @import("wait.zig");
const getters = @import("getters.zig");
const setters = @import("setters.zig");

pub const CommandCtx = types.CommandCtx;

/// Dispatch a session-level command. Returns true if handled.
pub fn dispatchSessionCommand(session: *cdp.Session, command: anytype, ctx: CommandCtx) !bool {
    switch (command) {
        .navigate => try navigation.navigate(session, ctx),
        .screenshot => try capture.screenshot(session, ctx),
        .pdf => try capture.pdf(session, ctx),
        .evaluate => try evaluate_cmd.evaluate(session, ctx),
        .network => helpers.network(),
        .cookies => try cookies_cmd.cookies(session, ctx),
        .storage => try storage_cmd.webStorage(session, ctx),
        .snapshot => try capture.snapshot(session, ctx),
        .click => try elements.click(session, ctx),
        .dblclick => try elements.dblclick(session, ctx),
        .focus => try elements.focus(session, ctx),
        .type => try elements.typeText(session, ctx),
        .fill => try elements.fill(session, ctx),
        .select => try elements.selectOption(session, ctx),
        .hover => try elements.hover(session, ctx),
        .check => try elements.check(session, ctx),
        .uncheck => try elements.uncheck(session, ctx),
        .scroll => try scroll_cmd.scroll(session, ctx),
        .scrollintoview => try scroll_cmd.scrollIntoView(session, ctx),
        .drag => try drag_cmd.drag(session, ctx),
        .get => try getters.get(session, ctx),
        .upload => try upload_cmd.upload(session, ctx),
        .back => try navigation.back(session),
        .forward => try navigation.forward(session),
        .reload => try navigation.reload(session),
        .press => try keyboard.press(session, ctx),
        .keydown => try keyboard.keyDown(session, ctx),
        .keyup => try keyboard.keyUp(session, ctx),
        .wait => try wait_cmd.wait(session, ctx),
        .mouse => try mouse_cmd.mouse(session, ctx),
        .set => try setters.set(session, ctx),
        else => {
            std.debug.print("Warning: unhandled command in dispatchSessionCommand\n", .{});
            return false;
        },
    }
    return true;
}
