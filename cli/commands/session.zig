//! Session management command implementation.
//!
//! Provides commands for listing, creating, showing, and deleting sessions.

const std = @import("std");
const session_mod = @import("../session.zig");
const config_mod = @import("../config.zig");

/// Session command - list, show, create, delete sessions
pub fn session(session_ctx: *const session_mod.SessionContext, positional: []const []const u8) !void {
    const allocator = session_ctx.allocator;
    const io = session_ctx.io;

    if (positional.len == 0) {
        // Show current session info
        std.debug.print("Current session: {s}\n", .{session_ctx.name});

        // Show config path
        const config_path = session_ctx.configPath() catch null;
        if (config_path) |cp| {
            std.debug.print("Config: {s}\n", .{cp});
            allocator.free(cp);
        }

        // Show session details if config exists
        if (session_ctx.loadConfig()) |cfg| {
            var config = cfg;
            defer config.deinit(allocator);
            if (config.port != 9222) std.debug.print("Port: {}\n", .{config.port});
            if (config.ws_url) |ws| std.debug.print("WebSocket URL: {s}\n", .{ws});
            if (config.viewport_width) |w| {
                if (config.viewport_height) |h| {
                    std.debug.print("Viewport: {}x{}\n", .{ w, h });
                }
            }
            if (config.device_name) |d| std.debug.print("Device: {s}\n", .{d});
        }
        return;
    }

    const subcmd = positional[0];

    if (std.mem.eql(u8, subcmd, "list")) {
        try listSessions(allocator, io, session_ctx.name);
    } else if (std.mem.eql(u8, subcmd, "show")) {
        const name = if (positional.len >= 2) positional[1] else session_ctx.name;
        try showSession(allocator, io, name);
    } else if (std.mem.eql(u8, subcmd, "create")) {
        if (positional.len < 2) {
            std.debug.print("Error: session create requires a name\n", .{});
            std.debug.print("Usage: zchrome session create <name>\n", .{});
            return;
        }
        try createSession(allocator, io, positional[1]);
    } else if (std.mem.eql(u8, subcmd, "delete")) {
        if (positional.len < 2) {
            std.debug.print("Error: session delete requires a name\n", .{});
            std.debug.print("Usage: zchrome session delete <name>\n", .{});
            return;
        }
        try deleteSession(allocator, io, positional[1]);
    } else {
        std.debug.print("Unknown session command: {s}\n", .{subcmd});
        printSessionHelp();
    }
}

/// List all sessions
fn listSessions(allocator: std.mem.Allocator, io: std.Io, current_session: []const u8) !void {
    var sessions = session_mod.listSessions(allocator, io) catch |err| {
        std.debug.print("Error listing sessions: {}\n", .{err});
        return;
    };
    defer {
        for (sessions.items) |s| allocator.free(s);
        sessions.deinit(allocator);
    }

    if (sessions.items.len == 0) {
        std.debug.print("No sessions found.\n", .{});
        return;
    }

    std.debug.print("Sessions:\n", .{});
    for (sessions.items) |name| {
        const marker: []const u8 = if (std.mem.eql(u8, name, current_session)) " (current)" else "";
        std.debug.print("  {s}{s}\n", .{ name, marker });
    }
    std.debug.print("\nTotal: {} session(s)\n", .{sessions.items.len});
}

/// Show session details
fn showSession(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !void {
    if (!session_mod.sessionExists(allocator, io, name)) {
        std.debug.print("Session not found: {s}\n", .{name});
        return;
    }

    std.debug.print("Session: {s}\n", .{name});

    const session_dir = session_mod.getSessionDir(allocator, io, name) catch null;
    if (session_dir) |sd| {
        std.debug.print("Directory: {s}\n", .{sd});
        allocator.free(sd);
    }

    const cfg = session_mod.loadSessionConfig(allocator, io, name);
    if (cfg) |c| {
        var config = c;
        defer config.deinit(allocator);
        if (config.port != 9222) std.debug.print("Port: {}\n", .{config.port});
        if (config.ws_url) |ws| std.debug.print("WebSocket URL: {s}\n", .{ws});
        if (config.chrome_path) |cp| std.debug.print("Chrome: {s}\n", .{cp});
        if (config.data_dir) |dd| std.debug.print("Data dir: {s}\n", .{dd});
        if (config.viewport_width) |w| {
            if (config.viewport_height) |h| {
                std.debug.print("Viewport: {}x{}\n", .{ w, h });
            }
        }
        if (config.device_name) |d| std.debug.print("Device: {s}\n", .{d});
        if (config.user_agent) |ua| std.debug.print("User Agent: {s}\n", .{ua});
    } else {
        std.debug.print("(no config)\n", .{});
    }
}

/// Create a new session
fn createSession(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !void {
    if (session_mod.sessionExists(allocator, io, name)) {
        std.debug.print("Session already exists: {s}\n", .{name});
        return;
    }

    session_mod.createSession(allocator, io, name) catch |err| {
        std.debug.print("Error creating session: {}\n", .{err});
        return;
    };

    std.debug.print("Created session: {s}\n", .{name});
    std.debug.print("Use: zchrome --session {s} <command>\n", .{name});
}

/// Delete a session
fn deleteSession(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !void {
    if (std.mem.eql(u8, name, "default")) {
        std.debug.print("Error: Cannot delete the 'default' session\n", .{});
        return;
    }

    if (!session_mod.sessionExists(allocator, io, name)) {
        std.debug.print("Session not found: {s}\n", .{name});
        return;
    }

    session_mod.deleteSession(allocator, io, name) catch |err| {
        std.debug.print("Error deleting session: {}\n", .{err});
        return;
    };

    std.debug.print("Deleted session: {s}\n", .{name});
}

/// Print session command help
pub fn printSessionHelp() void {
    std.debug.print(
        \\Usage: zchrome session [subcommand]
        \\
        \\Manage named sessions for isolated Chrome configurations.
        \\
        \\Subcommands:
        \\  session              Show current session info
        \\  session list         List all sessions
        \\  session show [name]  Show session details (default: current)
        \\  session create <n>   Create new session
        \\  session delete <n>   Delete a session
        \\
        \\Global flag:
        \\  --session <name>     Use a specific session for all commands
        \\
        \\Environment variable:
        \\  ZCHROME_SESSION      Default session name when --session not provided
        \\
        \\Examples:
        \\  zchrome session list
        \\  zchrome --session work connect
        \\  set ZCHROME_SESSION=work && zchrome navigate https://example.com
        \\
    , .{});
}
