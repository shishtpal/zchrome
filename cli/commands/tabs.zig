//! Unified tab and window management commands.
//!
//! This module provides shared implementations for tab/window operations
//! used by both CLI (runner.zig) and REPL (interactive/commands.zig).

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");

pub const CommandCtx = types.CommandCtx;

/// Result of tab operations
pub const TabResult = struct {
    /// Target ID of the affected tab (for new/switch operations)
    target_id: ?[]const u8 = null,
    /// Whether the session needs to be switched (REPL-specific)
    should_switch_session: bool = false,
    /// Session ID if a new session was created
    session_id: ?[]const u8 = null,
    /// Action that was performed
    action: Action = .list,

    pub const Action = enum {
        list,
        new,
        close,
        switch_tab,
    };
};

/// Unified tab command implementation.
/// Returns a TabResult that callers can use to update their state.
pub fn cmdTab(
    browser: *cdp.Browser,
    allocator: std.mem.Allocator,
    ctx: CommandCtx,
    current_target_id: ?[]const u8,
) !TabResult {
    var target = cdp.Target.init(browser.connection);

    // Check for --help
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printTabHelp();
            return .{};
        }
    }

    // tab new [url]
    if (ctx.positional.len >= 1 and std.mem.eql(u8, ctx.positional[0], "new")) {
        const url = if (ctx.positional.len >= 2) ctx.positional[1] else "about:blank";
        const target_id = try target.createTarget(allocator, url);
        std.debug.print("New tab: {s}\n", .{target_id});
        return .{
            .target_id = target_id,
            .action = .new,
        };
    }

    // tab close [n]
    if (ctx.positional.len >= 1 and std.mem.eql(u8, ctx.positional[0], "close")) {
        const page_tabs = try browser.pages();
        defer {
            for (page_tabs) |*p| p.*.deinit(allocator);
            allocator.free(page_tabs);
        }
        if (page_tabs.len == 0) {
            std.debug.print("No tabs open\n", .{});
            return .{ .action = .close };
        }
        var close_idx: usize = page_tabs.len - 1;
        if (ctx.positional.len >= 2) {
            close_idx = std.fmt.parseInt(usize, ctx.positional[1], 10) catch {
                std.debug.print("Invalid tab number: {s}\n", .{ctx.positional[1]});
                return .{ .action = .close };
            };
            if (close_idx == 0 or close_idx > page_tabs.len) {
                std.debug.print("Tab number out of range (1-{})\n", .{page_tabs.len});
                return .{ .action = .close };
            }
            close_idx -= 1;
        }
        const closed_target_id = page_tabs[close_idx].target_id;
        const success = try target.closeTarget(closed_target_id);
        if (success) {
            std.debug.print("Closed tab {}: {s}\n", .{ close_idx + 1, page_tabs[close_idx].title });
            // Check if we closed the current tab
            const closed_current = current_target_id != null and
                std.mem.eql(u8, current_target_id.?, closed_target_id);
            return .{
                .should_switch_session = closed_current,
                .action = .close,
            };
        } else {
            std.debug.print("Failed to close tab\n", .{});
        }
        return .{ .action = .close };
    }

    // tab <n> — switch to tab n
    if (ctx.positional.len >= 1) {
        const tab_num = std.fmt.parseInt(usize, ctx.positional[0], 10) catch {
            std.debug.print("Unknown subcommand: {s}\n", .{ctx.positional[0]});
            printTabHelp();
            return .{};
        };
        const page_tabs = try browser.pages();
        defer {
            for (page_tabs) |*p| p.*.deinit(allocator);
            allocator.free(page_tabs);
        }
        if (tab_num == 0 or tab_num > page_tabs.len) {
            std.debug.print("Tab number out of range (1-{})\n", .{page_tabs.len});
            return .{};
        }
        const selected = page_tabs[tab_num - 1];
        try target.activateTarget(selected.target_id);

        // Attach to target and get session ID
        const session_id = try target.attachToTarget(allocator, selected.target_id, true);
        const target_id_copy = try allocator.dupe(u8, selected.target_id);

        std.debug.print("Switched to tab {}: {s} ({s})\n", .{ tab_num, selected.title, selected.url });
        return .{
            .target_id = target_id_copy,
            .session_id = session_id,
            .should_switch_session = true,
            .action = .switch_tab,
        };
    }

    // Default: list tabs
    const page_tabs = try browser.pages();
    defer {
        for (page_tabs) |*p| p.*.deinit(allocator);
        allocator.free(page_tabs);
    }
    if (page_tabs.len == 0) {
        std.debug.print("No tabs open\n", .{});
        return .{};
    }
    for (page_tabs, 1..) |t, i| {
        const marker: []const u8 = if (current_target_id != null and
            std.mem.eql(u8, t.target_id, current_target_id.?)) "* " else "  ";
        std.debug.print("{s}{}: {s:<30} {s}\n", .{ marker, i, t.title, t.url });
    }
    std.debug.print("\nTotal: {} tab(s). * = current\n", .{page_tabs.len});
    return .{};
}

/// Unified window command implementation.
pub fn cmdWindow(browser: *cdp.Browser, ctx: CommandCtx) !void {
    // Check for --help
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printWindowHelp();
            return;
        }
    }

    if (ctx.positional.len >= 1 and std.mem.eql(u8, ctx.positional[0], "new")) {
        var result = try browser.connection.sendCommand("Target.createTarget", .{
            .url = "about:blank",
            .newWindow = true,
        }, null);
        result.deinit(ctx.allocator);
        std.debug.print("New window opened\n", .{});
        return;
    }

    printWindowHelp();
}

pub fn printTabHelp() void {
    std.debug.print(
        \\Usage: tab [subcommand]
        \\
        \\  tab                  List open tabs
        \\  tab new [url]        Open new tab
        \\  tab <n>              Switch to tab n
        \\  tab close [n]        Close tab n (default: current)
        \\
    , .{});
}

pub fn printWindowHelp() void {
    std.debug.print(
        \\Usage: window <subcommand>
        \\
        \\  window new           Open new browser window
        \\
    , .{});
}
