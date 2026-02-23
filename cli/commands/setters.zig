//! Set commands: viewport, device, useragent, geo, offline, headers, credentials, media.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const config_mod = @import("../config.zig");
const emulation = @import("emulation.zig");

pub const CommandCtx = types.CommandCtx;

pub fn set(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printSetHelp();
            return;
        }
    }

    if (ctx.positional.len == 0) {
        printSetUsage();
        return;
    }

    const sub = ctx.positional[0];

    // Load config for persistence
    var config = config_mod.loadConfig(ctx.allocator, ctx.io) orelse config_mod.Config{};
    defer config.deinit(ctx.allocator);

    if (std.mem.eql(u8, sub, "viewport")) {
        if (ctx.positional.len < 3) {
            std.debug.print("Usage: set viewport <width> <height>\n", .{});
            return;
        }
        const w = std.fmt.parseInt(u32, ctx.positional[1], 10) catch {
            std.debug.print("Error: Invalid width\n", .{});
            return;
        };
        const h = std.fmt.parseInt(u32, ctx.positional[2], 10) catch {
            std.debug.print("Error: Invalid height\n", .{});
            return;
        };

        try emulation.applyViewport(session, w, h, 1.0, false);
        _ = try session.sendCommand("Page.reload", .{});

        config.viewport_width = w;
        config.viewport_height = h;
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);
        std.debug.print("Viewport set to {}x{} (page reloaded)\n", .{ w, h });
    } else if (std.mem.eql(u8, sub, "device")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: set device <name>\n", .{});
            printDeviceList();
            return;
        }
        const device_name = ctx.positional[1];
        const device = getDeviceMetrics(device_name) orelse {
            std.debug.print("Unknown device: {s}\n", .{device_name});
            printDeviceList();
            return;
        };

        try emulation.applyViewport(session, device.width, device.height, device.scale, device.mobile);
        if (device.user_agent) |ua| {
            try emulation.applyUserAgent(session, ua);
        }
        _ = try session.sendCommand("Page.reload", .{});

        if (config.device_name) |old| ctx.allocator.free(old);
        config.device_name = ctx.allocator.dupe(u8, device_name) catch null;
        config.viewport_width = device.width;
        config.viewport_height = device.height;
        if (device.user_agent) |ua| {
            if (config.user_agent) |old| ctx.allocator.free(old);
            config.user_agent = ctx.allocator.dupe(u8, ua) catch null;
        }
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);
        std.debug.print("Device emulation: {s} ({}x{}, page reloaded)\n", .{ device_name, device.width, device.height });
    } else if (std.mem.eql(u8, sub, "geo")) {
        if (ctx.positional.len < 3) {
            std.debug.print("Usage: set geo <lat> <lng>\n", .{});
            return;
        }
        const lat = std.fmt.parseFloat(f64, ctx.positional[1]) catch {
            std.debug.print("Error: Invalid latitude\n", .{});
            return;
        };
        const lng = std.fmt.parseFloat(f64, ctx.positional[2]) catch {
            std.debug.print("Error: Invalid longitude\n", .{});
            return;
        };

        try emulation.applyGeolocation(session, lat, lng);

        config.geo_lat = lat;
        config.geo_lng = lng;
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);
        std.debug.print("Geolocation set to {d}, {d}\n", .{ lat, lng });
    } else if (std.mem.eql(u8, sub, "offline")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: set offline <on|off>\n", .{});
            return;
        }
        const offline = std.mem.eql(u8, ctx.positional[1], "on");

        try emulation.applyOfflineMode(session, offline);

        config.offline = offline;
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);
        std.debug.print("Offline mode: {}\n", .{offline});
    } else if (std.mem.eql(u8, sub, "headers")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: set headers <json>\n", .{});
            std.debug.print("Example: set headers '{{\"X-Custom\": \"value\"}}'\n", .{});
            return;
        }
        const json_str = ctx.positional[1];

        // Validate JSON
        const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, json_str, .{}) catch {
            std.debug.print("Error: Invalid JSON\n", .{});
            return;
        };
        defer parsed.deinit();

        if (parsed.value != .object) {
            std.debug.print("Error: Headers must be a JSON object\n", .{});
            return;
        }

        // Save to config (applied on next navigate/session)
        if (config.headers) |old| ctx.allocator.free(old);
        config.headers = ctx.allocator.dupe(u8, json_str) catch null;
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);
        std.debug.print("HTTP headers saved (applied on next navigate)\n", .{});
    } else if (std.mem.eql(u8, sub, "credentials")) {
        if (ctx.positional.len < 3) {
            std.debug.print("Usage: set credentials <username> <password>\n", .{});
            return;
        }
        const username = ctx.positional[1];
        const password = ctx.positional[2];

        // Save to config (applied on next navigate/session)
        if (config.auth_user) |old| ctx.allocator.free(old);
        config.auth_user = ctx.allocator.dupe(u8, username) catch null;
        if (config.auth_pass) |old| ctx.allocator.free(old);
        config.auth_pass = ctx.allocator.dupe(u8, password) catch null;
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);
        std.debug.print("HTTP basic auth saved (applied on next navigate)\n", .{});
    } else if (std.mem.eql(u8, sub, "media")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: set media <dark|light>\n", .{});
            return;
        }
        const scheme = ctx.positional[1];
        if (!std.mem.eql(u8, scheme, "dark") and !std.mem.eql(u8, scheme, "light")) {
            std.debug.print("Error: Use 'dark' or 'light'\n", .{});
            return;
        }

        try emulation.applyMediaFeature(session, scheme);
        _ = try session.sendCommand("Page.reload", .{});

        if (config.media_feature) |old| ctx.allocator.free(old);
        config.media_feature = ctx.allocator.dupe(u8, scheme) catch null;
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);
        std.debug.print("Color scheme set to {s} (page reloaded)\n", .{scheme});
    } else if (std.mem.eql(u8, sub, "useragent") or std.mem.eql(u8, sub, "ua")) {
        if (ctx.positional.len < 2) {
            std.debug.print("Usage: set useragent <name|custom-string>\n", .{});
            printUserAgentList();
            return;
        }
        const ua_input = ctx.positional[1];

        // Check if it's a built-in user agent name
        const ua_string = getUserAgent(ua_input) orelse ua_input;

        try emulation.applyUserAgent(session, ua_string);
        _ = try session.sendCommand("Page.reload", .{});

        if (config.user_agent) |old| ctx.allocator.free(old);
        config.user_agent = ctx.allocator.dupe(u8, ua_string) catch null;
        try config_mod.saveConfig(config, ctx.allocator, ctx.io);

        // Show friendly name if it was a preset
        if (getUserAgent(ua_input) != null) {
            std.debug.print("User agent set to {s} (applies to all requests, page reloaded)\n", .{ua_input});
        } else {
            std.debug.print("User agent set (applies to all requests, page reloaded)\n", .{});
        }
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{sub});
        printSetUsage();
    }
}

const DeviceMetrics = struct {
    width: u32,
    height: u32,
    scale: f64,
    mobile: bool,
    user_agent: ?[]const u8,
};

fn getDeviceMetrics(name: []const u8) ?DeviceMetrics {
    const devices = [_]struct { name: []const u8, metrics: DeviceMetrics }{
        .{ .name = "iPhone 14", .metrics = .{ .width = 390, .height = 844, .scale = 3.0, .mobile = true, .user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" } },
        .{ .name = "iPhone 14 Pro", .metrics = .{ .width = 393, .height = 852, .scale = 3.0, .mobile = true, .user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" } },
        .{ .name = "iPhone 15", .metrics = .{ .width = 393, .height = 852, .scale = 3.0, .mobile = true, .user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" } },
        .{ .name = "Pixel 7", .metrics = .{ .width = 412, .height = 915, .scale = 2.625, .mobile = true, .user_agent = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36" } },
        .{ .name = "Pixel 8", .metrics = .{ .width = 412, .height = 915, .scale = 2.625, .mobile = true, .user_agent = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36" } },
        .{ .name = "iPad", .metrics = .{ .width = 768, .height = 1024, .scale = 2.0, .mobile = true, .user_agent = "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" } },
        .{ .name = "iPad Pro", .metrics = .{ .width = 1024, .height = 1366, .scale = 2.0, .mobile = true, .user_agent = "Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" } },
        .{ .name = "Desktop", .metrics = .{ .width = 1920, .height = 1080, .scale = 1.0, .mobile = false, .user_agent = null } },
        .{ .name = "Desktop HD", .metrics = .{ .width = 1366, .height = 768, .scale = 1.0, .mobile = false, .user_agent = null } },
        .{ .name = "Desktop 4K", .metrics = .{ .width = 3840, .height = 2160, .scale = 1.0, .mobile = false, .user_agent = null } },
    };

    for (devices) |d| {
        if (std.ascii.eqlIgnoreCase(d.name, name)) return d.metrics;
    }
    return null;
}

fn printDeviceList() void {
    std.debug.print("Available devices:\n", .{});
    std.debug.print("  iPhone 14, iPhone 14 Pro, iPhone 15\n", .{});
    std.debug.print("  Pixel 7, Pixel 8\n", .{});
    std.debug.print("  iPad, iPad Pro\n", .{});
    std.debug.print("  Desktop, Desktop HD, Desktop 4K\n", .{});
}

fn getUserAgent(name: []const u8) ?[]const u8 {
    const user_agents = [_]struct { name: []const u8, ua: []const u8 }{
        // Desktop browsers
        .{ .name = "chrome", .ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" },
        .{ .name = "chrome-mac", .ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" },
        .{ .name = "chrome-linux", .ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" },
        .{ .name = "edge", .ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0" },
        .{ .name = "firefox", .ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0" },
        .{ .name = "firefox-mac", .ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0" },
        .{ .name = "safari", .ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15" },
        .{ .name = "brave", .ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Brave/120" },
        .{ .name = "opera", .ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0" },
        .{ .name = "vivaldi", .ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Vivaldi/6.4" },
        // Mobile browsers
        .{ .name = "chrome-android", .ua = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36" },
        .{ .name = "chrome-ios", .ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.0.0 Mobile/15E148 Safari/604.1" },
        .{ .name = "safari-ios", .ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1" },
        .{ .name = "firefox-android", .ua = "Mozilla/5.0 (Android 14; Mobile; rv:121.0) Gecko/121.0 Firefox/121.0" },
        .{ .name = "samsung", .ua = "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.0.0 Mobile Safari/537.36" },
        // Bots/crawlers
        .{ .name = "googlebot", .ua = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" },
        .{ .name = "bingbot", .ua = "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)" },
        // Special
        .{ .name = "curl", .ua = "curl/8.4.0" },
    };

    for (user_agents) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.ua;
    }
    return null;
}

fn printUserAgentList() void {
    std.debug.print("Built-in user agents:\n", .{});
    std.debug.print("  Desktop: chrome, chrome-mac, chrome-linux, edge, firefox, firefox-mac, safari, brave, opera, vivaldi\n", .{});
    std.debug.print("  Mobile:  chrome-android, chrome-ios, safari-ios, firefox-android, samsung\n", .{});
    std.debug.print("  Bots:    googlebot, bingbot\n", .{});
    std.debug.print("  Other:   curl\n", .{});
    std.debug.print("\nOr provide a custom user agent string in quotes.\n", .{});
}

fn printSetUsage() void {
    std.debug.print(
        \\Usage: set <subcommand> [args]
        \\
        \\Subcommands:
        \\  viewport <w> <h>      Set viewport size
        \\  device <name>         Emulate device
        \\  useragent <name|str>  Set user agent (alias: ua)
        \\  geo <lat> <lng>       Set geolocation
        \\  offline <on|off>      Toggle offline mode
        \\  headers <json>        Set extra HTTP headers
        \\  credentials <u> <p>   Set HTTP basic auth
        \\  media <dark|light>    Set prefers-color-scheme
        \\
    , .{});
}

pub fn printSetHelp() void {
    std.debug.print(
        \\Usage: set <subcommand> [args]
        \\
        \\Configure browser session settings. Settings are applied immediately
        \\via CDP and persisted to zchrome.json for future sessions.
        \\
        \\Subcommands:
        \\  set viewport <w> <h>        Set viewport size in pixels
        \\  set device <name>           Emulate device (viewport + user agent)
        \\  set useragent <name|str>    Set user agent (alias: ua)
        \\  set geo <lat> <lng>         Set geolocation coordinates
        \\  set offline <on|off>        Toggle offline mode
        \\  set headers <json>          Set extra HTTP headers
        \\  set credentials <u> <p>     Set HTTP basic auth credentials
        \\  set media <dark|light>      Set prefers-color-scheme
        \\
        \\Available devices:
        \\  iPhone 14, iPhone 14 Pro, iPhone 15
        \\  Pixel 7, Pixel 8
        \\  iPad, iPad Pro
        \\  Desktop, Desktop HD, Desktop 4K
        \\
        \\Available user agents:
        \\  Desktop: chrome, chrome-mac, chrome-linux, edge, firefox, safari, brave, opera, vivaldi
        \\  Mobile:  chrome-android, chrome-ios, safari-ios, firefox-android, samsung
        \\  Bots:    googlebot, bingbot
        \\
        \\Examples:
        \\  set viewport 1920 1080          # Full HD viewport
        \\  set device "iPhone 14"          # Emulate iPhone 14
        \\  set useragent firefox           # Use Firefox user agent
        \\  set ua "Custom Agent/1.0"       # Custom user agent
        \\  set geo 37.7749 -122.4194       # San Francisco
        \\  set offline on                  # Simulate offline
        \\  set headers '{{"X-Custom":"val"}}'  # Add custom header
        \\  set credentials admin secret    # HTTP basic auth
        \\  set media dark                  # Dark mode
        \\
    , .{});
}
