//! Mouse commands: move, down, up, wheel.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const config_mod = @import("../config.zig");
const actions_mod = @import("../actions/mod.zig");

pub const CommandCtx = types.CommandCtx;

/// Parse button string to MouseButton enum
pub fn parseMouseButton(button_str: ?[]const u8) cdp.MouseButton {
    if (button_str) |b| {
        if (std.mem.eql(u8, b, "left")) return .left;
        if (std.mem.eql(u8, b, "right")) return .right;
        if (std.mem.eql(u8, b, "middle")) return .middle;
    }
    return .left; // default
}

/// Mouse command dispatcher - handles move, down, up, wheel subcommands
pub fn mouse(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printMouseHelp();
            return;
        }
    }

    if (ctx.positional.len == 0) {
        printMouseUsage();
        return;
    }

    const subcommand = ctx.positional[0];
    const args = if (ctx.positional.len > 1) ctx.positional[1..] else &[_][]const u8{};

    if (std.mem.eql(u8, subcommand, "move")) {
        try mouseMoveCmd(session, ctx.allocator, ctx.io, args);
    } else if (std.mem.eql(u8, subcommand, "down")) {
        try mouseDownCmd(session, ctx.allocator, ctx.io, args);
    } else if (std.mem.eql(u8, subcommand, "up")) {
        try mouseUpCmd(session, ctx.allocator, ctx.io, args);
    } else if (std.mem.eql(u8, subcommand, "wheel")) {
        try mouseWheelCmd(session, ctx.allocator, ctx.io, args);
    } else {
        std.debug.print("Unknown mouse subcommand: {s}\n", .{subcommand});
        printMouseUsage();
    }
}

fn printMouseUsage() void {
    std.debug.print(
        \\Usage: mouse <subcommand> [args]
        \\
        \\Subcommands:
        \\  move <x> <y>        Move mouse to coordinates
        \\  down [button]       Press mouse button (left/right/middle, default: left)
        \\  up [button]         Release mouse button
        \\  wheel <dy> [dx]     Scroll mouse wheel
        \\
        \\Examples:
        \\  mouse move 100 200
        \\  mouse down left
        \\  mouse up
        \\  mouse wheel -100
        \\
    , .{});
}

fn mouseMoveCmd(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: mouse move <x> <y>\n", .{});
        return;
    }

    const x = std.fmt.parseFloat(f64, args[0]) catch {
        std.debug.print("Error: Invalid x coordinate: {s}\n", .{args[0]});
        return error.InvalidArgument;
    };
    const y = std.fmt.parseFloat(f64, args[1]) catch {
        std.debug.print("Error: Invalid y coordinate: {s}\n", .{args[1]});
        return error.InvalidArgument;
    };

    try actions_mod.mouseMove(session, x, y);
    std.debug.print("Mouse moved to ({d}, {d})\n", .{ x, y });

    // Save position to config; defer runs after saveConfig below
    var config = config_mod.loadConfig(allocator, io) orelse config_mod.Config{};
    defer config.deinit(allocator);
    config.last_mouse_x = x;
    config.last_mouse_y = y;
    config_mod.saveConfig(config, allocator, io) catch |err| {
        std.debug.print("Warning: Could not save mouse position: {}\n", .{err});
    };
}

fn mouseDownCmd(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    const button = parseMouseButton(if (args.len > 0) args[0] else null);

    // Get position from config
    var config = config_mod.loadConfig(allocator, io) orelse config_mod.Config{};
    defer config.deinit(allocator);

    const x = config.last_mouse_x orelse blk: {
        std.debug.print("Warning: No mouse position set. Use 'mouse move <x> <y>' first.\n", .{});
        break :blk 0.0;
    };
    const y = config.last_mouse_y orelse 0.0;

    try actions_mod.mouseDownAt(session, x, y, button);
    std.debug.print("Mouse button {s} pressed at ({d}, {d})\n", .{ @tagName(button), x, y });
}

fn mouseUpCmd(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    const button = parseMouseButton(if (args.len > 0) args[0] else null);

    // Get position from config
    var config = config_mod.loadConfig(allocator, io) orelse config_mod.Config{};
    defer config.deinit(allocator);

    const x = config.last_mouse_x orelse blk: {
        std.debug.print("Warning: No mouse position set. Use 'mouse move <x> <y>' first.\n", .{});
        break :blk 0.0;
    };
    const y = config.last_mouse_y orelse 0.0;

    try actions_mod.mouseUpAt(session, x, y, button);
    std.debug.print("Mouse button {s} released at ({d}, {d})\n", .{ @tagName(button), x, y });
}

fn mouseWheelCmd(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: mouse wheel <dy> [dx]\n", .{});
        return;
    }

    const delta_y = std.fmt.parseFloat(f64, args[0]) catch {
        std.debug.print("Error: Invalid delta_y: {s}\n", .{args[0]});
        return error.InvalidArgument;
    };
    const delta_x: f64 = if (args.len > 1)
        std.fmt.parseFloat(f64, args[1]) catch 0
    else
        0;

    // Get position from config
    var config = config_mod.loadConfig(allocator, io) orelse config_mod.Config{};
    defer config.deinit(allocator);

    const x = config.last_mouse_x orelse blk: {
        std.debug.print("Warning: No mouse position set. Use 'mouse move <x> <y>' first.\n", .{});
        break :blk 0.0;
    };
    const y = config.last_mouse_y orelse 0.0;

    try actions_mod.mouseWheelAt(session, x, y, delta_x, delta_y);
    std.debug.print("Mouse wheel scrolled (dx={d}, dy={d})\n", .{ delta_x, delta_y });
}

pub fn printMouseHelp() void {
    std.debug.print(
        \\Usage: mouse <subcommand> [args]
        \\
        \\Subcommands:
        \\  mouse move <x> <y>       Move mouse to coordinates
        \\  mouse down [button]      Press mouse button (left/right/middle, default: left)
        \\  mouse up [button]        Release mouse button
        \\  mouse wheel <dy> [dx]    Scroll mouse wheel
        \\
        \\Examples:
        \\  mouse move 100 200
        \\  mouse down left
        \\  mouse up
        \\  mouse wheel -100
        \\
    , .{});
}
