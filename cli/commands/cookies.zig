//! Cookie management commands.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const CommandCtx = types.CommandCtx;

/// Check if a cookie domain matches a filter.
/// Cookie domains may have a leading dot (e.g. ".example.com") meaning they
/// apply to all subdomains. The filter is matched against the bare domain
/// (without leading dot) so that "example.com" matches ".example.com",
/// "example.com", and "sub.example.com" but NOT "notexample.com".
fn cookieDomainMatches(cookie_domain: []const u8, filter: []const u8) bool {
    // Strip leading dot from cookie domain for comparison
    const bare_domain = if (cookie_domain.len > 0 and cookie_domain[0] == '.')
        cookie_domain[1..]
    else
        cookie_domain;

    // Strip leading dot from filter too
    const bare_filter = if (filter.len > 0 and filter[0] == '.')
        filter[1..]
    else
        filter;

    // Exact match
    if (std.mem.eql(u8, bare_domain, bare_filter)) return true;

    // Subdomain match: bare_domain ends with ".bare_filter"
    if (bare_domain.len > bare_filter.len) {
        const offset = bare_domain.len - bare_filter.len;
        if (bare_domain[offset - 1] == '.' and std.mem.eql(u8, bare_domain[offset..], bare_filter)) return true;
    }

    return false;
}

pub fn cookies(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printCookiesHelp();
            return;
        }
    }

    var page = cdp.Page.init(session);
    try page.enable();

    var storage = cdp.Storage.init(session);

    const args = ctx.positional;

    // Subcommand dispatch: set, clear, get, delete, export, import
    if (args.len > 0 and std.mem.eql(u8, args[0], "set")) {
        // cookies set <name> <value>
        if (args.len < 3) {
            std.debug.print("Usage: cookies set <name> <value>\n", .{});
            return;
        }
        // Get current page URL for the cookie domain
        var runtime = cdp.Runtime.init(session);
        try runtime.enable();
        const page_url = runtime.evaluateAs([]const u8, "window.location.href") catch null;
        try storage.setCookies(&.{.{
            .name = args[1],
            .value = args[2],
            .url = page_url,
        }});
        std.debug.print("Cookie set: {s}={s}\n", .{ args[1], args[2] });
        return;
    }

    if (args.len > 0 and std.mem.eql(u8, args[0], "clear")) {
        // cookies clear [domain]
        if (args.len > 1) {
            const domain_filter = args[1];
            const all_cookies = try storage.getCookies(ctx.allocator, null);
            defer {
                for (all_cookies) |*c| c.deinit(ctx.allocator);
                ctx.allocator.free(all_cookies);
            }
            var count: usize = 0;
            for (all_cookies) |cookie| {
                if (cookieDomainMatches(cookie.domain, domain_filter)) {
                    try storage.deleteCookies(cookie.name, null, cookie.domain);
                    count += 1;
                }
            }
            std.debug.print("Cleared {} cookies for domain: {s}\n", .{ count, domain_filter });
        } else {
            try storage.clearCookies();
            std.debug.print("All cookies cleared\n", .{});
        }
        return;
    }

    if (args.len > 0 and std.mem.eql(u8, args[0], "get")) {
        // cookies get <name> [domain]
        if (args.len < 2) {
            std.debug.print("Usage: cookies get <name> [domain]\n", .{});
            return;
        }
        const name_filter = args[1];
        const domain_filter = if (args.len > 2) args[2] else null;

        const all_cookies = try storage.getCookies(ctx.allocator, null);
        defer {
            for (all_cookies) |*c| c.deinit(ctx.allocator);
            ctx.allocator.free(all_cookies);
        }

        var found = false;
        for (all_cookies) |cookie| {
            if (std.mem.eql(u8, cookie.name, name_filter)) {
                if (domain_filter) |d| {
                    if (!cookieDomainMatches(cookie.domain, d)) continue;
                }
                found = true;
                std.debug.print("Name: {s}\nValue: {s}\nDomain: {s}\nPath: {s}\nExpires: {d}\nSecure: {}\nHttpOnly: {}\n\n", .{
                    cookie.name, cookie.value, cookie.domain, cookie.path, cookie.expires, cookie.secure, cookie.http_only,
                });
            }
        }
        if (!found) std.debug.print("Cookie not found: {s}\n", .{name_filter});
        return;
    }

    if (args.len > 0 and std.mem.eql(u8, args[0], "delete")) {
        // cookies delete <name> [domain]
        if (args.len < 2) {
            std.debug.print("Usage: cookies delete <name> [domain]\n", .{});
            return;
        }
        const name_filter = args[1];
        const domain_filter = if (args.len > 2) args[2] else null;

        const all_cookies = try storage.getCookies(ctx.allocator, null);
        defer {
            for (all_cookies) |*c| c.deinit(ctx.allocator);
            ctx.allocator.free(all_cookies);
        }

        var count: usize = 0;
        for (all_cookies) |cookie| {
            if (std.mem.eql(u8, cookie.name, name_filter)) {
                if (domain_filter) |d| {
                    if (!cookieDomainMatches(cookie.domain, d)) continue;
                }
                try storage.deleteCookies(cookie.name, null, cookie.domain);
                count += 1;
            }
        }
        std.debug.print("Deleted {} cookie(s)\n", .{count});
        return;
    }

    if (args.len > 0 and std.mem.eql(u8, args[0], "export")) {
        // cookies export <path> [domain]
        if (args.len < 2) {
            std.debug.print("Usage: cookies export <path> [domain]\n", .{});
            return;
        }
        const path = args[1];
        const domain_filter = if (args.len > 2) args[2] else null;

        const all_cookies = try storage.getCookies(ctx.allocator, null);
        defer {
            for (all_cookies) |*c| c.deinit(ctx.allocator);
            ctx.allocator.free(all_cookies);
        }

        // Build a filtered list of cookies (shallow copy - strings still owned by all_cookies)
        var filtered: std.ArrayList(cdp.Cookie) = .empty;
        defer filtered.deinit(ctx.allocator);

        for (all_cookies) |cookie| {
            if (domain_filter) |d| {
                if (!cookieDomainMatches(cookie.domain, d)) continue;
            }
            try filtered.append(ctx.allocator, cookie);
        }

        // Serialize the filtered cookies while all_cookies is still alive (strings are valid)
        const json_str = try cdp.json.stringify(ctx.allocator, filtered.items);
        defer ctx.allocator.free(json_str);

        try helpers.writeFile(ctx.io, path, json_str);
        std.debug.print("Exported {} cookies to {s}\n", .{ filtered.items.len, path });
        return;
    }

    if (args.len > 0 and std.mem.eql(u8, args[0], "import")) {
        // cookies import <path> [domain]
        if (args.len < 2) {
            std.debug.print("Usage: cookies import <path> [domain]\n", .{});
            return;
        }
        const path = args[1];
        const domain_override = if (args.len > 2) args[2] else null;

        const dir = std.Io.Dir.cwd();
        const content = dir.readFileAlloc(ctx.io, path, ctx.allocator, std.Io.Limit.limited(1 * 1024 * 1024)) catch |err| {
            std.debug.print("Error reading file {s}: {}\n", .{ path, err });
            return err;
        };
        defer ctx.allocator.free(content);

        const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, content, .{}) catch |err| {
            std.debug.print("Error parsing JSON from {s}: {}\n", .{ path, err });
            return;
        };
        defer parsed.deinit();

        if (parsed.value != .array) {
            std.debug.print("Error: JSON file must contain an array of cookies\n", .{});
            return;
        }

        var count: usize = 0;
        var params: std.ArrayList(cdp.CookieParam) = .empty;
        try params.ensureTotalCapacity(ctx.allocator, parsed.value.array.items.len);
        defer params.deinit(ctx.allocator);

        for (parsed.value.array.items) |item| {
            if (item != .object) continue;
            const name = if (item.object.get("name")) |v| (if (v == .string) v.string else "") else "";
            const value = if (item.object.get("value")) |v| (if (v == .string) v.string else "") else "";
            var domain = if (item.object.get("domain")) |v| (if (v == .string) v.string else "") else "";
            const path_str = if (item.object.get("path")) |v| (if (v == .string) v.string else "/") else "/";
            const secure = if (item.object.get("secure")) |v| (if (v == .bool) v.bool else false) else false;
            // Handle both httpOnly (JSON standard) and http_only (internal field name if leaked)
            const http_only = if (item.object.get("httpOnly")) |v| (if (v == .bool) v.bool else false) else if (item.object.get("http_only")) |v| (if (v == .bool) v.bool else false) else false;

            if (domain_override) |d| {
                domain = d;
            }

            try params.append(ctx.allocator, .{
                .name = name,
                .value = value,
                .domain = domain,
                .path = path_str,
                .secure = secure,
                .http_only = http_only,
            });
            count += 1;
        }

        if (params.items.len > 0) {
            try storage.setCookies(params.items);
        }
        std.debug.print("Imported {} cookies\n", .{count});
        return;
    }

    // Default: list [domain]
    const domain_filter = if (args.len > 0) args[0] else null;

    const cookie_list = try storage.getCookies(ctx.allocator, null);
    defer {
        for (cookie_list) |*c| {
            var cookie = c.*;
            cookie.deinit(ctx.allocator);
        }
        ctx.allocator.free(cookie_list);
    }

    if (cookie_list.len == 0) {
        std.debug.print("No cookies found\n", .{});
        return;
    }

    std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ "Name", "Value", "Domain" });
    std.debug.print("{s:-<90}\n", .{""});
    var count: usize = 0;
    for (cookie_list) |cookie| {
        if (domain_filter) |d| {
            if (!cookieDomainMatches(cookie.domain, d)) continue;
        }
        std.debug.print("{s:<30} {s:<40} {s:<20}\n", .{ cookie.name, cookie.value, cookie.domain });
        count += 1;
    }
    if (count == 0 and domain_filter != null) {
        std.debug.print("No cookies found for domain: {s}\n", .{domain_filter.?});
    }
}

pub fn printCookiesHelp() void {
    std.debug.print(
        \\Usage: cookies [subcommand] [args]
        \\
        \\Subcommands:
        \\  cookies                        List all cookies
        \\  cookies <domain>               List cookies for specific domain
        \\  cookies set <name> <value>     Set a cookie
        \\  cookies get <name> [domain]    Get specific cookie
        \\  cookies delete <name> [domain] Delete specific cookie
        \\  cookies clear [domain]         Clear all cookies (or for domain)
        \\  cookies export <path> [domain] Export cookies to JSON file
        \\  cookies import <path> [domain] Import cookies from JSON file
        \\
        \\Examples:
        \\  cookies set session_id abc123
        \\  cookies get session_id .example.com
        \\  cookies export cookies.json
        \\  cookies clear .example.com
        \\
    , .{});
}
