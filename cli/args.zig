const std = @import("std");
const cdp = @import("cdp");
const session_mod = @import("session.zig");

pub const Args = struct {
    url: ?[]const u8 = null,
    headless: cdp.Headless = .off,
    port: ?u16 = null,
    chrome_path: ?[]const u8 = null,
    data_dir: ?[]const u8 = null,
    timeout_ms: u32 = 30_000,
    verbose: bool = false,
    output: ?[]const u8 = null,
    use_target: ?[]const u8 = null,
    full_page: bool = false,
    io: std.Io = undefined,
    command: Command,
    positional: []const []const u8,
    session_arg: ?[]const u8 = null,
    session_ctx: ?*const session_mod.SessionContext = null,
    snap_interactive: bool = false,
    snap_compact: bool = false,
    snap_depth: ?usize = null,
    snap_selector: ?[]const u8 = null,
    snap_mark: bool = false,
    wait_text: ?[]const u8 = null,
    wait_url: ?[]const u8 = null,
    wait_load: ?[]const u8 = null,
    wait_fn: ?[]const u8 = null,
    click_js: bool = false,
    replay_retries: u32 = 3,
    replay_retry_delay: u32 = 100,
    replay_fallback: ?[]const u8 = null,
    replay_resume: bool = false,
    replay_from: ?usize = null,

    pub const Command = enum {
        open,
        connect,
        navigate,
        screenshot,
        pdf,
        evaluate,
        network,
        cookies,
        storage,
        tab,
        window,
        version,
        list_targets,
        pages,
        interactive,
        snapshot,
        click,
        dblclick,
        focus,
        type,
        fill,
        select,
        multiselect,
        hover,
        check,
        uncheck,
        scroll,
        scrollintoview,
        drag,
        get,
        upload,
        back,
        forward,
        reload,
        press,
        keydown,
        keyup,
        wait,
        mouse,
        cursor,
        set,
        dialog,
        dev,
        session,
        diff,
        dom,
        help,
    };

    pub fn deinit(self: *Args, allocator: std.mem.Allocator) void {
        for (self.positional) |p| allocator.free(p);
        allocator.free(self.positional);
        if (self.url) |u| allocator.free(u);
        if (self.chrome_path) |p| allocator.free(p);
        if (self.data_dir) |d| allocator.free(d);
        if (self.output) |o| allocator.free(o);
        if (self.use_target) |t| allocator.free(t);
        if (self.snap_selector) |s| allocator.free(s);
        if (self.wait_text) |w| allocator.free(w);
        if (self.wait_url) |w| allocator.free(w);
        if (self.wait_load) |w| allocator.free(w);
        if (self.wait_fn) |w| allocator.free(w);
        if (self.session_arg) |s| allocator.free(s);
        if (self.replay_fallback) |f| allocator.free(f);
    }
};

pub fn parseArgs(allocator: std.mem.Allocator, args: std.process.Args) !Args {
    var iter = try std.process.Args.Iterator.initAllocator(args, allocator);
    defer iter.deinit();

    var positional: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (positional.items) |p| allocator.free(p);
        positional.deinit(allocator);
    }

    var command: Args.Command = .help;
    var url: ?[]const u8 = null;
    var headless: cdp.Headless = .off;
    var port: ?u16 = null;
    var chrome_path: ?[]const u8 = null;
    var data_dir: ?[]const u8 = null;
    var timeout_ms: u32 = 30_000;
    var verbose: bool = false;
    var output: ?[]const u8 = null;
    var use_target: ?[]const u8 = null;
    var full_page: bool = false;
    var snap_interactive: bool = false;
    var snap_compact: bool = false;
    var snap_depth: ?usize = null;
    var snap_selector: ?[]const u8 = null;
    var snap_mark: bool = false;
    var wait_text: ?[]const u8 = null;
    var wait_url: ?[]const u8 = null;
    var wait_load: ?[]const u8 = null;
    var wait_fn: ?[]const u8 = null;
    var click_js: bool = false;
    var session_arg: ?[]const u8 = null;
    var replay_retries: u32 = 3;
    var replay_retry_delay: u32 = 100;
    var replay_fallback: ?[]const u8 = null;
    var replay_resume: bool = false;
    var replay_from: ?usize = null;

    _ = iter.skip();

    while (iter.next()) |arg| {
        const is_negative_number = arg.len > 1 and arg[0] == '-' and (arg[1] >= '0' and arg[1] <= '9');
        if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-' and !is_negative_number) {
            if (std.mem.eql(u8, arg, "-i")) {
                snap_interactive = true;
            } else if (std.mem.eql(u8, arg, "-c")) {
                snap_compact = true;
            } else if (std.mem.eql(u8, arg, "-d")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_depth = try std.fmt.parseInt(usize, val, 10);
            } else if (std.mem.eql(u8, arg, "-s")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_selector = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "-m")) {
                snap_mark = true;
            }
        } else if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--url")) {
                const val = iter.next() orelse return error.MissingArgument;
                url = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--use")) {
                const val = iter.next() orelse return error.MissingArgument;
                use_target = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--headless")) {
                const val = iter.next() orelse "new";
                headless = if (std.mem.eql(u8, val, "off"))
                    .off
                else if (std.mem.eql(u8, val, "old"))
                    .old
                else
                    .new;
            } else if (std.mem.eql(u8, arg, "--port")) {
                const val = iter.next() orelse return error.MissingArgument;
                port = try std.fmt.parseInt(u16, val, 10);
            } else if (std.mem.eql(u8, arg, "--chrome")) {
                const val = iter.next() orelse return error.MissingArgument;
                chrome_path = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--data-dir")) {
                const val = iter.next() orelse return error.MissingArgument;
                data_dir = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--session")) {
                const val = iter.next() orelse return error.MissingArgument;
                session_arg = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--timeout")) {
                const val = iter.next() orelse return error.MissingArgument;
                timeout_ms = try std.fmt.parseInt(u32, val, 10);
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                verbose = true;
            } else if (std.mem.eql(u8, arg, "--full")) {
                full_page = true;
            } else if (std.mem.eql(u8, arg, "--output")) {
                const val = iter.next() orelse return error.MissingArgument;
                output = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--help")) {
                if (command == .help) {
                    command = .help;
                    break;
                }
                try positional.append(allocator, try allocator.dupe(u8, arg));
            } else if (std.mem.eql(u8, arg, "--interactive-only")) {
                snap_interactive = true;
            } else if (std.mem.eql(u8, arg, "--compact")) {
                snap_compact = true;
            } else if (std.mem.eql(u8, arg, "--depth")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_depth = try std.fmt.parseInt(usize, val, 10);
            } else if (std.mem.eql(u8, arg, "--selector")) {
                const val = iter.next() orelse return error.MissingArgument;
                snap_selector = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--mark")) {
                snap_mark = true;
            } else if (std.mem.eql(u8, arg, "--text")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_text = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--match")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_url = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--load")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_load = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--fn")) {
                const val = iter.next() orelse return error.MissingArgument;
                wait_fn = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--js")) {
                click_js = true;
            } else if (std.mem.eql(u8, arg, "--retries")) {
                const val = iter.next() orelse return error.MissingArgument;
                replay_retries = try std.fmt.parseInt(u32, val, 10);
            } else if (std.mem.eql(u8, arg, "--retry-delay")) {
                const val = iter.next() orelse return error.MissingArgument;
                replay_retry_delay = try std.fmt.parseInt(u32, val, 10);
            } else if (std.mem.eql(u8, arg, "--fallback")) {
                const val = iter.next() orelse return error.MissingArgument;
                replay_fallback = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, arg, "--resume")) {
                replay_resume = true;
            } else if (std.mem.eql(u8, arg, "--from")) {
                const val = iter.next() orelse return error.MissingArgument;
                replay_from = try std.fmt.parseInt(usize, val, 10);
            } else {
                try positional.append(allocator, try allocator.dupe(u8, arg));
            }
        } else {
            if (command == .help) {
                if (std.mem.eql(u8, arg, "list-targets")) {
                    command = .list_targets;
                } else if (std.mem.eql(u8, arg, "scrollinto")) {
                    command = .scrollintoview;
                } else if (std.mem.eql(u8, arg, "key")) {
                    command = .press;
                } else {
                    command = std.meta.stringToEnum(Args.Command, arg) orelse .help;
                }
            } else {
                try positional.append(allocator, try allocator.dupe(u8, arg));
            }
        }
    }

    return .{
        .url = url,
        .headless = headless,
        .port = port,
        .chrome_path = chrome_path,
        .data_dir = data_dir,
        .timeout_ms = timeout_ms,
        .verbose = verbose,
        .output = output,
        .use_target = use_target,
        .full_page = full_page,
        .command = command,
        .positional = try positional.toOwnedSlice(allocator),
        .snap_interactive = snap_interactive,
        .snap_compact = snap_compact,
        .snap_depth = snap_depth,
        .snap_selector = snap_selector,
        .snap_mark = snap_mark,
        .wait_text = wait_text,
        .wait_url = wait_url,
        .wait_load = wait_load,
        .wait_fn = wait_fn,
        .click_js = click_js,
        .session_arg = session_arg,
        .replay_retries = replay_retries,
        .replay_retry_delay = replay_retry_delay,
        .replay_fallback = replay_fallback,
        .replay_resume = replay_resume,
        .replay_from = replay_from,
    };
}

const USAGE_TEXT = @embedFile("usage.txt");

pub fn printUsage() void {
    std.debug.print("{s}", .{USAGE_TEXT});
}
