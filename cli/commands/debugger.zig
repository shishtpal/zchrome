//! JavaScript debugger commands.
//!
//! Provides access to the Debugger domain for setting breakpoints,
//! stepping through code, and inspecting execution state.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const CommandCtx = types.CommandCtx;

pub fn debug(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printDebugHelp();
            return;
        }
    }

    const args = ctx.positional;

    if (args.len == 0) {
        printDebugUsage();
        return;
    }

    if (std.mem.eql(u8, args[0], "enable")) {
        try enableCmd(session);
    } else if (std.mem.eql(u8, args[0], "scripts")) {
        try scriptsCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "disable")) {
        try disableCmd(session);
    } else if (std.mem.eql(u8, args[0], "pause")) {
        try pauseCmd(session);
    } else if (std.mem.eql(u8, args[0], "resume")) {
        try resumeCmd(session);
    } else if (std.mem.eql(u8, args[0], "step-over")) {
        try stepOverCmd(session);
    } else if (std.mem.eql(u8, args[0], "step-into")) {
        try stepIntoCmd(session);
    } else if (std.mem.eql(u8, args[0], "step-out")) {
        try stepOutCmd(session);
    } else if (std.mem.eql(u8, args[0], "break")) {
        try breakCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "unbreak")) {
        try unbreakCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "source")) {
        try sourceCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "exceptions")) {
        try exceptionsCmd(session, ctx);
    } else {
        std.debug.print("Unknown debug subcommand: {s}\n", .{args[0]});
        printDebugUsage();
    }
}

// ─── enable / disable ───────────────────────────────────────────────────────

fn enableCmd(session: *cdp.Session) !void {
    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    std.debug.print("Debugger enabled.\n", .{});
    std.debug.print("Use 'debug scripts' to list available scripts.\n", .{});
}

// ─── scripts ────────────────────────────────────────────────────────────────

fn scriptsCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    // Use Runtime to get script info via performance.getEntries()
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js =
        \\(function() {
        \\  const scripts = [];
        \\  // Get external scripts
        \\  document.querySelectorAll('script[src]').forEach((s, i) => {
        \\    scripts.push({ index: i, type: 'external', src: s.src });
        \\  });
        \\  // Get inline scripts
        \\  document.querySelectorAll('script:not([src])').forEach((s, i) => {
        \\    const preview = s.textContent.trim().substring(0, 50).replace(/\s+/g, ' ');
        \\    scripts.push({ index: scripts.length, type: 'inline', preview: preview + '...' });
        \\  });
        \\  return JSON.stringify(scripts);
        \\})()
    ;

    var remote_obj = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch |err| {
        std.debug.print("Error getting scripts: {}\n", .{err});
        return;
    };
    defer remote_obj.deinit(ctx.allocator);

    const result_str = if (remote_obj.value) |v| v.asString() orelse null else null;
    if (result_str == null) {
        std.debug.print("No scripts found\n", .{});
        return;
    }

    var parsed = json.parse(ctx.allocator, result_str.?, .{}) catch {
        std.debug.print("Error parsing scripts\n", .{});
        return;
    };
    defer parsed.deinit(ctx.allocator);

    std.debug.print("Scripts on page:\n", .{});
    std.debug.print("================\n\n", .{});

    if (parsed.asArray()) |arr| {
        for (arr) |script| {
            const idx = switch (script.get("index").?) {
                .integer => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => 0,
            };
            const script_type = if (script.get("type")) |t| t.asString() orelse "unknown" else "unknown";

            if (std.mem.eql(u8, script_type, "external")) {
                const src = if (script.get("src")) |s| s.asString() orelse "(unknown)" else "(unknown)";
                std.debug.print("[{d}] {s}\n", .{ idx, src });
            } else {
                const preview = if (script.get("preview")) |p| p.asString() orelse "" else "";
                std.debug.print("[{d}] <inline> {s}\n", .{ idx, preview });
            }
        }
    }

    std.debug.print("\nNote: These are DOM script elements, not CDP script IDs.\n", .{});
    std.debug.print("Use 'debug source <index>' to view script content.\n", .{});
}

fn disableCmd(session: *cdp.Session) !void {
    var dbg = cdp.Debugger.init(session);
    try dbg.disable();
    std.debug.print("Debugger disabled.\n", .{});
}

// ─── pause / resume ─────────────────────────────────────────────────────────

fn pauseCmd(session: *cdp.Session) !void {
    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    try dbg.pause();
    std.debug.print("Execution paused.\n", .{});
}

fn resumeCmd(session: *cdp.Session) !void {
    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    try dbg.@"resume"();
    std.debug.print("Execution resumed.\n", .{});
}

// ─── stepping ───────────────────────────────────────────────────────────────

fn stepOverCmd(session: *cdp.Session) !void {
    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    try dbg.stepOver();
    std.debug.print("Stepped over.\n", .{});
}

fn stepIntoCmd(session: *cdp.Session) !void {
    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    try dbg.stepInto();
    std.debug.print("Stepped into.\n", .{});
}

fn stepOutCmd(session: *cdp.Session) !void {
    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    try dbg.stepOut();
    std.debug.print("Stepped out.\n", .{});
}

// ─── breakpoints ────────────────────────────────────────────────────────────

fn breakCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 3) {
        std.debug.print("Usage: debug break <url> <line> [condition]\n", .{});
        std.debug.print("Example: debug break https://example.com/app.js 42\n", .{});
        return;
    }

    const url = args[1];
    const line_number = std.fmt.parseInt(i64, args[2], 10) catch {
        std.debug.print("Invalid line number: {s}\n", .{args[2]});
        return;
    };

    const condition: ?[]const u8 = if (args.len > 3) args[3] else null;

    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();

    const result = try dbg.setBreakpointByUrl(
        ctx.allocator,
        line_number,
        url,
        null, // url_regex
        null, // script_hash
        null, // column_number
        condition,
    );
    defer {
        ctx.allocator.free(result.breakpoint_id);
        for (result.locations) |*loc| loc.deinit(ctx.allocator);
        ctx.allocator.free(result.locations);
    }

    std.debug.print("Breakpoint set: {s}\n", .{result.breakpoint_id});
    std.debug.print("  URL: {s}\n", .{url});
    std.debug.print("  Line: {}\n", .{line_number});
    if (condition) |c| {
        std.debug.print("  Condition: {s}\n", .{c});
    }
    if (result.locations.len > 0) {
        std.debug.print("  Resolved at {} location(s)\n", .{result.locations.len});
    }
}

fn unbreakCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 2) {
        std.debug.print("Usage: debug unbreak <breakpointId>\n", .{});
        return;
    }

    const breakpoint_id = args[1];

    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    try dbg.removeBreakpoint(breakpoint_id);

    std.debug.print("Breakpoint removed: {s}\n", .{breakpoint_id});
}

// ─── source ─────────────────────────────────────────────────────────────────

fn sourceCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 2) {
        std.debug.print("Usage: debug source <index>\n", .{});
        std.debug.print("  Get script content by index (from 'debug scripts')\n", .{});
        return;
    }

    const index = std.fmt.parseInt(usize, args[1], 10) catch {
        std.debug.print("Invalid index: {s}\n", .{args[1]});
        return;
    };

    // Use JavaScript to get script content by index
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var js_buf: [512]u8 = undefined;
    const js = std.fmt.bufPrint(&js_buf,
        \\(function() {{
        \\  const scripts = document.querySelectorAll('script');
        \\  const script = scripts[{d}];
        \\  if (!script) return JSON.stringify({{ error: 'Script not found at index {d}' }});
        \\  if (script.src) {{
        \\    return JSON.stringify({{ error: 'External script - fetch from: ' + script.src }});
        \\  }}
        \\  return JSON.stringify({{ source: script.textContent }});
        \\}})()
    , .{ index, index }) catch {
        std.debug.print("Error building JS\n", .{});
        return;
    };

    var remote_obj = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch |err| {
        std.debug.print("Error getting script: {}\n", .{err});
        return;
    };
    defer remote_obj.deinit(ctx.allocator);

    const result_str = if (remote_obj.value) |v| v.asString() orelse null else null;
    if (result_str == null) {
        std.debug.print("Error: No data returned\n", .{});
        return;
    }

    var parsed = json.parse(ctx.allocator, result_str.?, .{}) catch {
        std.debug.print("Error parsing result\n", .{});
        return;
    };
    defer parsed.deinit(ctx.allocator);

    // Check for error
    if (parsed.get("error")) |err_val| {
        if (err_val.asString()) |err_msg| {
            std.debug.print("{s}\n", .{err_msg});
            return;
        }
    }

    const source = if (parsed.get("source")) |v| v.asString() orelse "" else "";

    // Output to file or stdout
    if (ctx.output) |output_path| {
        try helpers.writeFile(ctx.io, output_path, source);
        std.debug.print("Script source saved to: {s}\n", .{output_path});
    } else {
        // Print first 100 lines
        var line_count: usize = 0;
        var iter = std.mem.splitScalar(u8, source, '\n');
        while (iter.next()) |line| {
            line_count += 1;
            std.debug.print("{d:4} | {s}\n", .{ line_count, line });
            if (line_count >= 100) {
                std.debug.print("... (truncated, use -o <file> to save full source)\n", .{});
                break;
            }
        }
    }
}

// ─── exceptions ─────────────────────────────────────────────────────────────

fn exceptionsCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 2) {
        std.debug.print("Usage: debug exceptions <none|uncaught|all>\n", .{});
        return;
    }

    const state_str = args[1];
    const state: cdp.PauseOnExceptionsState = if (std.mem.eql(u8, state_str, "none"))
        .none
    else if (std.mem.eql(u8, state_str, "uncaught"))
        .uncaught
    else if (std.mem.eql(u8, state_str, "all"))
        .all
    else {
        std.debug.print("Invalid state: {s}\n", .{state_str});
        std.debug.print("Valid values: none, uncaught, all\n", .{});
        return;
    };

    var dbg = cdp.Debugger.init(session);
    _ = try dbg.enable();
    try dbg.setPauseOnExceptions(state);

    std.debug.print("Pause on exceptions: {s}\n", .{state_str});
}

// ─── Help ───────────────────────────────────────────────────────────────────

fn printDebugUsage() void {
    std.debug.print("Usage: debug <subcommand> [options]\n", .{});
    std.debug.print("\nSubcommands: enable, disable, scripts, source, pause, resume,\n", .{});
    std.debug.print("             step-over, step-into, step-out, break, unbreak, exceptions\n", .{});
    std.debug.print("Use 'debug --help' for details.\n", .{});
}

pub fn printDebugHelp() void {
    const help =
        \\JavaScript Debugger Commands
        \\============================
        \\
        \\Debug JavaScript execution in the browser.
        \\
        \\USAGE:
        \\  debug <subcommand> [options]
        \\
        \\SUBCOMMANDS:
        \\  enable                          Enable debugger
        \\  disable                         Disable debugger
        \\  scripts                         List scripts on the page
        \\  source <index> [-o file]        Get inline script content by index
        \\  pause                           Pause execution
        \\  resume                          Resume execution
        \\  step-over                       Step over next statement
        \\  step-into                       Step into function call
        \\  step-out                        Step out of current function
        \\  break <url> <line> [condition]  Set breakpoint
        \\  unbreak <breakpointId>          Remove breakpoint
        \\  exceptions <none|uncaught|all>  Set pause on exceptions
        \\
        \\EXAMPLES:
        \\  debug scripts                   # List all scripts
        \\  debug source 0                  # View first inline script
        \\  debug source 2 -o script.js    # Save third script to file
        \\  debug pause
        \\  debug step-over
        \\  debug break https://example.com/app.js 42
        \\  debug exceptions uncaught
        \\
        \\NOTES:
        \\  - 'debug scripts' lists DOM script elements
        \\  - 'debug source' only works for inline scripts
        \\  - External scripts must be fetched from their URL
        \\
    ;
    std.debug.print("{s}", .{help});
}
