//! Action handlers with fallback selector support.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("../commands/types.zig");
const elements = @import("../commands/elements.zig");
const macro = @import("macro/mod.zig");

/// Try an action with fallback selectors
pub fn tryWithFallbackSelectors(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
    comptime action_fn: fn (*cdp.Session, types.CommandCtx) anyerror!void,
) void {
    // Build list of selectors to try
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    for (selectors, 0..) |sel, idx| {
        var pos_args: [1][]const u8 = .{sel};
        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = &pos_args,
        };
        action_fn(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try fill command with fallback selectors
pub fn tryWithFallbackSelectorsFill(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
) void {
    const value = cmd.value orelse return;
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    for (selectors, 0..) |sel, idx| {
        var pos_args: [2][]const u8 = .{ sel, value };
        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = &pos_args,
        };
        elements.fill(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try type command with fallback selectors
pub fn tryWithFallbackSelectorsType(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
) void {
    const value = cmd.value orelse return;
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    for (selectors, 0..) |sel, idx| {
        var pos_args: [2][]const u8 = .{ sel, value };
        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = &pos_args,
        };
        elements.typeText(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try select command with fallback selectors
pub fn tryWithFallbackSelectorsSelect(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
) void {
    const value = cmd.value orelse return;
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    for (selectors, 0..) |sel, idx| {
        var pos_args: [2][]const u8 = .{ sel, value };
        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = &pos_args,
        };
        elements.selectOption(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try multiselect command with fallback selectors (value is JSON array)
pub fn tryWithFallbackSelectorsMultiselect(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
) void {
    const value = cmd.value orelse return;
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    const actions_mod = @import("../actions/mod.zig");

    for (selectors, 0..) |sel, idx| {
        var resolved = actions_mod.resolveSelector(allocator, io, sel, null) catch {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: selector resolution failed\n", .{});
            return;
        };
        defer resolved.deinit();

        actions_mod.multiselectOptions(session, allocator, &resolved, value) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}

/// Try upload command with fallback selectors
pub fn tryWithFallbackSelectorsUpload(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    cmd: macro.MacroCommand,
    files: [][]const u8,
) void {
    const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
        var single: [1][]const u8 = .{sel};
        break :blk &single;
    } else return;

    const upload_mod = @import("../commands/upload.zig");

    for (selectors, 0..) |sel, idx| {
        // Build args array: selector + files
        var args_list: std.ArrayList([]const u8) = .empty;
        defer args_list.deinit(allocator);

        args_list.append(allocator, sel) catch continue;
        for (files) |file| {
            args_list.append(allocator, file) catch continue;
        }

        const ctx = types.CommandCtx{
            .allocator = allocator,
            .io = io,
            .positional = args_list.items,
        };

        upload_mod.upload(session, ctx) catch |err| {
            if (idx + 1 < selectors.len) {
                std.debug.print("    (trying fallback selector...)\n", .{});
                continue;
            }
            std.debug.print("    Error: {}\n", .{err});
            return;
        };
        return; // Success
    }
}
