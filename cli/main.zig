const std = @import("std");
const cdp = @import("cdp");
const args_mod = @import("args.zig");
const cloud = @import("cloud.zig");
const config_mod = @import("config.zig");
const globals = @import("globals.zig");
const impl = @import("commands/mod.zig");
const runner = @import("runner.zig");
const session_mod = @import("session.zig");

const Args = args_mod.Args;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = args_mod.parseArgs(allocator, init.minimal.args) catch {
        args_mod.printUsage();
        std.process.exit(1);
    };
    args.io = init.io;
    defer args.deinit(allocator);

    if (args.command == .help) {
        args_mod.printUsage();
        return;
    }

    if (args.chrome_path == null) {
        if (init.environ_map.get("ZCHROME_BROWSER")) |v| {
            if (v.len > 0) args.chrome_path = allocator.dupe(u8, v) catch null;
        }
    }
    if (args.port == null) {
        if (init.environ_map.get("ZCHROME_PORT")) |v| {
            args.port = std.fmt.parseInt(u16, v, 10) catch null;
        }
    }
    if (args.data_dir == null) {
        if (init.environ_map.get("ZCHROME_DATA_DIR")) |v| {
            if (v.len > 0) args.data_dir = allocator.dupe(u8, v) catch null;
        }
    }
    if (!args.verbose) {
        if (init.environ_map.get("ZCHROME_VERBOSE")) |v| {
            args.verbose = std.mem.eql(u8, v, "1") or std.mem.eql(u8, v, "true");
        }
    }
    // Set global verbose flag for use throughout the codebase
    globals.verbose = args.verbose;
    if (args.headless == .off) {
        if (init.environ_map.get("ZCHROME_HEADLESS")) |v| {
            if (std.mem.eql(u8, v, "new")) {
                args.headless = .new;
            } else if (std.mem.eql(u8, v, "old")) {
                args.headless = .old;
            }
        }
    }
    // Provider from environment variable
    if (args.provider == null) {
        if (init.environ_map.get("ZCHROME_PROVIDER")) |v| {
            if (v.len > 0) args.provider = allocator.dupe(u8, v) catch null;
        }
    }

    session_mod.migrateToSessions(allocator, init.io) catch {};

    const session_name = session_mod.resolveSessionName(allocator, init.environ_map, args.session_arg) catch {
        std.debug.print("Error resolving session name\n", .{});
        std.process.exit(1);
    };
    var session_ctx = session_mod.SessionContext{
        .name = session_name,
        .allocator = allocator,
        .io = init.io,
        .init = init,
        .verbose = args.verbose,
    };
    defer session_ctx.deinit();

    args.session_ctx = &session_ctx;

    if (args.command == .session) {
        try impl.sessionCmd(&session_ctx, args.positional);
        return;
    }

    if (args.command == .provider) {
        try impl.providerCmd(&session_ctx, args.positional, init.environ_map);
        return;
    }

    if (args.command == .extensions) {
        try impl.extensionsCmd(&session_ctx, args.positional);
        return;
    }

    var config = session_ctx.loadConfig() orelse config_mod.Config{};
    defer config.deinit(allocator);

    if (args.chrome_path == null and config.chrome_path != null) {
        args.chrome_path = allocator.dupe(u8, config.chrome_path.?) catch null;
    }
    if (args.data_dir == null and config.data_dir != null) {
        args.data_dir = allocator.dupe(u8, config.data_dir.?) catch null;
    }
    if (args.url == null and config.ws_url != null) {
        args.url = allocator.dupe(u8, config.ws_url.?) catch null;
    }
    if (args.port == null) {
        args.port = config.port;
    }

    // Merge ZCHROME_EXTENSIONS environment variable with config extensions
    if (init.environ_map.get("ZCHROME_EXTENSIONS")) |v| {
        if (v.len > 0) {
            var ext_list: std.ArrayList([]const u8) = .empty;
            // Copy existing config extensions
            if (config.extensions) |exts| {
                for (exts) |ext| {
                    ext_list.append(allocator, allocator.dupe(u8, ext) catch continue) catch {};
                }
            }
            // Parse and add env var extensions (comma-separated)
            var iter = std.mem.splitScalar(u8, v, ',');
            while (iter.next()) |path| {
                const trimmed = std.mem.trim(u8, path, " ");
                if (trimmed.len > 0) {
                    ext_list.append(allocator, allocator.dupe(u8, trimmed) catch continue) catch {};
                }
            }
            // Replace config.extensions with merged list
            if (config.extensions) |old| {
                for (old) |ext| allocator.free(ext);
                allocator.free(old);
            }
            config.extensions = ext_list.toOwnedSlice(allocator) catch null;
        }
    }

    // Determine effective provider (CLI flag > config > "local")
    const effective_provider = args.provider orelse config.provider orelse "local";
    const is_cloud_provider = !std.mem.eql(u8, effective_provider, "local");

    const needs_target = switch (args.command) {
        // navigate has its own page selection logic in cmdNavigate
        .screenshot, .pdf, .evaluate, .network, .cookies, .storage, .snapshot, .click, .dblclick, .focus, .type, .fill, .select, .multiselect, .hover, .check, .uncheck, .scroll, .scrollintoview, .drag, .get, .upload, .back, .forward, .reload, .press, .keydown, .keyup, .wait, .mouse, .cursor, .set, .dialog, .dev, .diff, .dom, .clipboard, .media => true,
        .navigate, .tab, .window, .version, .list_targets, .pages, .interactive, .open, .connect, .session, .provider, .extensions, .help => false,
    };
    // For cloud providers, don't use saved last_target as it may be stale across connections
    // Instead, let the command re-query targets (via withFirstPage or similar)
    if (needs_target and args.use_target == null and config.last_target != null and !is_cloud_provider) {
        args.use_target = allocator.dupe(u8, config.last_target.?) catch null;
    }

    // Validate extensions compatibility
    if (config.extensions != null and config.extensions.?.len > 0) {
        if (is_cloud_provider) {
            std.debug.print("Error: Cannot use extensions with cloud providers\n", .{});
            std.debug.print("Extensions require a local browser.\n", .{});
            std.process.exit(1);
        }
    }

    // Early --help check for commands that require browser connection
    // This prevents "Failed to connect" errors when user just wants help
    if (hasHelpFlag(args.positional)) {
        printCommandHelp(args.command);
        return;
    }

    switch (args.command) {
        .open => {
            if (is_cloud_provider) {
                const prov = cloud.getProviderOrExit(effective_provider, init.environ_map);
                try cloud.cloudOpen(.{
                    .allocator = allocator,
                    .init = init,
                    .session_ctx = &session_ctx,
                    .config = &config,
                    .provider = prov.provider,
                    .api_key = prov.api_key,
                    .verbose = args.verbose,
                    .timeout_ms = args.timeout_ms,
                });
            } else {
                try runner.cmdOpen(args, allocator, init.io, &config);
            }
            return;
        },
        .connect => {
            if (is_cloud_provider) {
                const prov = cloud.getProviderOrExit(effective_provider, init.environ_map);
                try cloud.cloudConnect(.{
                    .allocator = allocator,
                    .init = init,
                    .session_ctx = &session_ctx,
                    .config = &config,
                    .provider = prov.provider,
                    .api_key = prov.api_key,
                    .verbose = args.verbose,
                });
            } else {
                try runner.cmdConnect(args, allocator, init.io);
            }
            return;
        },
        else => {},
    }

    // For cloud providers, require explicit 'open' first
    if (is_cloud_provider) {
        cloud.requireCloudSession(effective_provider, args.url);
    }

    var is_connected = args.url != null;
    var browser: *cdp.Browser = undefined;

    if (args.url) |ws_url| {
        browser = cdp.Browser.connect(ws_url, allocator, init.io, .{ .verbose = args.verbose }) catch |err| {
            if (is_cloud_provider) {
                cloud.printCloudConnectionError(err);
            } else {
                std.debug.print("Failed to connect: {}\n", .{err});
            }
            std.process.exit(1);
        };
        is_connected = true;
    } else {
        browser = cdp.Browser.launch(.{
            .headless = args.headless,
            .executable_path = args.chrome_path,
            .allocator = allocator,
            .io = init.io,
            .timeout_ms = args.timeout_ms,
        }) catch |err| {
            std.debug.print("Failed to launch browser: {}\n", .{err});
            std.process.exit(1);
        };
    }
    defer if (is_connected) browser.disconnect() else browser.close();

    const is_page_url = if (args.url) |url|
        std.mem.indexOf(u8, url, "/devtools/page/") != null
    else
        false;

    if (is_page_url) {
        try runner.executeDirectly(browser, args, allocator);
    } else if (args.use_target) |tid| {
        try runner.executeOnTarget(browser, tid, args, allocator);
    } else {
        switch (args.command) {
            .navigate => try runner.cmdNavigate(browser, args, allocator),
            .screenshot => try runner.cmdScreenshot(browser, args, allocator),
            .pdf => try runner.cmdPdf(browser, args, allocator),
            .evaluate => try runner.cmdEvaluate(browser, args, allocator),
            .tab => try runner.cmdTab(browser, args, allocator),
            .window => try runner.cmdWindow(browser, args, allocator),
            .version => try runner.cmdVersion(browser, allocator),
            .list_targets => try runner.cmdListTargets(browser, allocator),
            .pages => try runner.cmdPages(browser, allocator),
            .interactive => try runner.cmdInteractive(browser, args, allocator),
            .snapshot => try runner.cmdSnapshot(browser, args, allocator),
            .open, .connect, .session, .provider, .help => unreachable,
            else => try runner.withFirstPage(browser, args, allocator),
        }
    }

    // Cleanup cloud session if --cleanup flag was set
    if (args.cleanup_session and is_cloud_provider) {
        if (cdp.getProvider(effective_provider)) |provider| {
            if (init.environ_map.get(provider.api_key_env_var)) |api_key| {
                cloud.cloudCleanup(.{
                    .allocator = allocator,
                    .init = init,
                    .session_ctx = &session_ctx,
                    .config = &config,
                    .provider = provider,
                    .api_key = api_key,
                    .verbose = args.verbose,
                });
            }
        }
    }
}

fn hasHelpFlag(positional: []const []const u8) bool {
    for (positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) return true;
    }
    return false;
}

fn printCommandHelp(command: Args.Command) void {
    switch (command) {
        .snapshot => impl.printSnapshotHelp(),
        .wait => impl.printWaitHelp(),
        .dom => impl.printDomHelp(),
        .cookies => impl.printCookiesHelp(),
        .storage => impl.printStorageHelp(),
        .get => impl.printGetHelp(),
        .set => impl.printSetHelp(),
        .mouse => impl.printMouseHelp(),
        .cursor => impl.printCursorHelp(),
        .network => impl.printNetworkHelp(),
        .dev => impl.printDevHelp(),
        .diff => impl.printDiffHelp(),
        .tab => impl.printTabHelp(),
        .window => impl.printWindowHelp(),
        .clipboard => impl.printClipboardHelp(),
        .media => impl.printMediaHelp(),
        .session => impl.printSessionHelp(),
        .extensions => impl.printExtensionsHelp(),
        else => args_mod.printUsage(),
    }
}
