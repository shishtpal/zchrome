//! Shared command implementations used by both CLI and interactive REPL.
//!
//! Each function takes a `*cdp.Session` and a `CommandCtx` containing
//! allocator, io, and positional arguments. This avoids duplicating
//! the command logic across main.zig and interactive/commands.zig.

const std = @import("std");
const cdp = @import("cdp");
const snapshot_mod = @import("snapshot.zig");
const config_mod = @import("config.zig");
const actions_mod = @import("actions/mod.zig");

pub const CommandCtx = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    positional: []const []const u8,
    output: ?[]const u8 = null,
    full_page: bool = false,
    // Snapshot options
    snap_interactive: bool = false,
    snap_compact: bool = false,
    snap_depth: ?usize = null,
    snap_selector: ?[]const u8 = null,
    // Wait options
    wait_text: ?[]const u8 = null,
    wait_url: ?[]const u8 = null,
    wait_load: ?[]const u8 = null,
    wait_fn: ?[]const u8 = null,
};

// ─── Navigation ─────────────────────────────────────────────────────────────

pub fn navigate(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: navigate <url>\n", .{});
        return;
    }

    const target_url = ctx.positional[0];
    var page = cdp.Page.init(session);
    try page.enable();

    var result = try page.navigate(ctx.allocator, target_url);
    defer result.deinit(ctx.allocator);

    if (result.error_text) |err| {
        std.debug.print("Navigation error: {s}\n", .{err});
        return;
    }

    var i: u32 = 0;
    while (i < 500000) : (i += 1) std.atomic.spinLoopHint();

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();
    const title = runtime.evaluateAs([]const u8, "document.title") catch "Unknown";
    std.debug.print("URL: {s}\nTitle: {s}\n", .{ target_url, title });
}

pub fn back(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    if (try page.goBack())
        std.debug.print("Navigated back\n", .{})
    else
        std.debug.print("No previous page in history\n", .{});
}

pub fn forward(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    if (try page.goForward())
        std.debug.print("Navigated forward\n", .{})
    else
        std.debug.print("No next page in history\n", .{});
}

pub fn reload(session: *cdp.Session) !void {
    var page = cdp.Page.init(session);
    try page.reload(null);
    std.debug.print("Page reloaded\n", .{});
}

// ─── Capture ────────────────────────────────────────────────────────────────

pub fn screenshot(session: *cdp.Session, ctx: CommandCtx) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();

    const screenshot_data = try page.captureScreenshot(ctx.allocator, .{
        .format = .png,
        .capture_beyond_viewport = if (ctx.full_page) true else null,
    });
    defer ctx.allocator.free(screenshot_data);

    const decoded = try cdp.base64.decodeAlloc(ctx.allocator, screenshot_data);
    defer ctx.allocator.free(decoded);

    const output_path = ctx.output orelse "screenshot.png";
    try writeFile(ctx.io, output_path, decoded);
    std.debug.print("Screenshot saved to {s} ({} bytes){s}\n", .{
        output_path,
        decoded.len,
        if (ctx.full_page) " (full page)" else "",
    });
}

pub fn pdf(session: *cdp.Session, ctx: CommandCtx) !void {
    var page = cdp.Page.init(session);
    try page.enable();

    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();

    const pdf_data = try page.printToPDF(ctx.allocator, .{});
    defer ctx.allocator.free(pdf_data);

    const decoded = try cdp.base64.decodeAlloc(ctx.allocator, pdf_data);
    defer ctx.allocator.free(decoded);

    const output_path = ctx.output orelse "page.pdf";
    try writeFile(ctx.io, output_path, decoded);
    std.debug.print("PDF saved to {s} ({} bytes)\n", .{ output_path, decoded.len });
}

pub fn snapshot(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag in positional args
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printSnapshotHelp();
            return;
        }
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js = try snapshot_mod.buildSnapshotJs(ctx.allocator, ctx.snap_selector, ctx.snap_depth);
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    const aria_tree = result.asString() orelse "(empty)";

    var processor = snapshot_mod.SnapshotProcessor.init(ctx.allocator);
    defer processor.deinit();

    const options = snapshot_mod.SnapshotOptions{
        .interactive = ctx.snap_interactive,
        .compact = ctx.snap_compact,
        .max_depth = ctx.snap_depth,
        .selector = ctx.snap_selector,
    };

    var snap = try processor.processAriaTree(aria_tree, options);
    defer snap.deinit();

    std.debug.print("{s}\n", .{snap.tree});
    std.debug.print("\n--- {} element(s) with refs ---\n", .{snap.refs.count()});

    const output_path = ctx.output orelse try config_mod.getSnapshotPath(ctx.allocator, ctx.io);
    defer if (ctx.output == null) ctx.allocator.free(output_path);

    try snapshot_mod.saveSnapshot(ctx.allocator, ctx.io, output_path, &snap);

    std.debug.print("\nSnapshot saved to: {s}\n", .{output_path});
    if (snap.refs.count() > 0) {
        std.debug.print("Use @e<N> refs in subsequent commands\n", .{});
    }
}

// ─── Inspection ─────────────────────────────────────────────────────────────

pub fn evaluate(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: evaluate <expression>\n", .{});
        return;
    }

    const expression = ctx.positional[0];
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    var result = try runtime.evaluate(ctx.allocator, expression, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |v| {
        switch (v) {
            .string => |s| std.debug.print("{s}\n", .{s}),
            .integer => |int_val| std.debug.print("{}\n", .{int_val}),
            .float => |f| std.debug.print("{d}\n", .{f}),
            .bool => |b| std.debug.print("{}\n", .{b}),
            .null => std.debug.print("null\n", .{}),
            else => std.debug.print("[complex value]\n", .{}),
        }
    } else {
        std.debug.print("{s}\n", .{result.description orelse "undefined"});
    }
}

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

        try writeFile(ctx.io, path, json_str);
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

pub fn webStorage(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printStorageHelp();
            return;
        }
    }

    if (ctx.positional.len == 0) {
        printStorageUsage();
        return;
    }

    const store_type = ctx.positional[0];
    const is_local = std.mem.eql(u8, store_type, "local");
    const is_session = std.mem.eql(u8, store_type, "session");

    if (!is_local and !is_session) {
        std.debug.print("Unknown storage type: {s}\n", .{store_type});
        printStorageUsage();
        return;
    }

    const js_obj: []const u8 = if (is_local) "localStorage" else "sessionStorage";
    const args = if (ctx.positional.len > 1) ctx.positional[1..] else &[_][]const u8{};

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // storage local set <key> <value>
    if (args.len >= 1 and std.mem.eql(u8, args[0], "set")) {
        if (args.len < 3) {
            std.debug.print("Usage: storage {s} set <key> <value>\n", .{store_type});
            return;
        }
        const js = try std.fmt.allocPrint(ctx.allocator,
            \\{s}.setItem({s}, {s})
        , .{
            js_obj,
            try jsStringLiteral(ctx.allocator, args[1]),
            try jsStringLiteral(ctx.allocator, args[2]),
        });
        defer ctx.allocator.free(js);
        var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
        defer result.deinit(ctx.allocator);
        std.debug.print("{s} set: {s}={s}\n", .{ store_type, args[1], args[2] });
        return;
    }

    // storage local clear
    if (args.len >= 1 and std.mem.eql(u8, args[0], "clear")) {
        const js = try std.fmt.allocPrint(ctx.allocator, "{s}.clear()", .{js_obj});
        defer ctx.allocator.free(js);
        var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
        defer result.deinit(ctx.allocator);
        std.debug.print("{s} storage cleared\n", .{store_type});
        return;
    }

    // storage local export <path>
    if (args.len >= 1 and std.mem.eql(u8, args[0], "export")) {
        if (args.len < 2) {
            std.debug.print("Usage: storage {s} export <path.json|yaml>\n", .{store_type});
            return;
        }
        const path = args[1];
        // JS: get all entries as JSON string
        const js = try std.fmt.allocPrint(ctx.allocator,
            \\JSON.stringify(Object.fromEntries(
            \\  Object.keys({s}).map(k => [k, {s}.getItem(k)])
            \\))
        , .{ js_obj, js_obj });
        defer ctx.allocator.free(js);
        var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
        defer result.deinit(ctx.allocator);
        const json_str = result.asString() orelse "{}";
        // Detect format by extension
        const output = if (cdp.yaml.isYamlPath(path))
            try cdp.yaml.jsonToYaml(ctx.allocator, json_str)
        else
            try ctx.allocator.dupe(u8, json_str);
        defer ctx.allocator.free(output);
        try writeFile(ctx.io, path, output);
        std.debug.print("Exported {s} storage to {s}\n", .{ store_type, path });
        return;
    }

    // storage local import <path>
    if (args.len >= 1 and std.mem.eql(u8, args[0], "import")) {
        if (args.len < 2) {
            std.debug.print("Usage: storage {s} import <path.json|yaml>\n", .{store_type});
            return;
        }
        const path = args[1];
        const dir = std.Io.Dir.cwd();
        const content = dir.readFileAlloc(ctx.io, path, ctx.allocator, std.Io.Limit.limited(1 * 1024 * 1024)) catch |err| {
            std.debug.print("Error reading file {s}: {}\n", .{ path, err });
            return err;
        };
        defer ctx.allocator.free(content);
        // Parse JSON (convert YAML to JSON first if needed)
        const is_yaml = cdp.yaml.isYamlPath(path);
        const json_str = if (is_yaml)
            try cdp.yaml.yamlToJson(ctx.allocator, content)
        else
            content;
        defer if (is_yaml) ctx.allocator.free(json_str);
        const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, json_str, .{}) catch |err| {
            std.debug.print("Error parsing JSON from {s}: {}\n", .{ path, err });
            return;
        };
        defer parsed.deinit();
        if (parsed.value != .object) {
            std.debug.print("Error: file must contain a JSON object\n", .{});
            return;
        }
        var count: usize = 0;
        var it = parsed.value.object.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* != .string) continue;
            const key_lit = try jsStringLiteral(ctx.allocator, entry.key_ptr.*);
            defer ctx.allocator.free(key_lit);
            const val_lit = try jsStringLiteral(ctx.allocator, entry.value_ptr.*.string);
            defer ctx.allocator.free(val_lit);
            const js_set = try std.fmt.allocPrint(ctx.allocator,
                \\{s}.setItem({s}, {s})
            , .{ js_obj, key_lit, val_lit });
            defer ctx.allocator.free(js_set);
            var r = try runtime.evaluate(ctx.allocator, js_set, .{ .return_by_value = true });
            defer r.deinit(ctx.allocator);
            count += 1;
        }
        std.debug.print("Imported {} entries into {s} storage\n", .{ count, store_type });
        return;
    }

    // storage local <key>  → get specific key
    if (args.len >= 1) {
        const js = try std.fmt.allocPrint(ctx.allocator, "{s}.getItem({s})", .{
            js_obj,
            try jsStringLiteral(ctx.allocator, args[0]),
        });
        defer ctx.allocator.free(js);
        var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
        defer result.deinit(ctx.allocator);
        if (result.value) |v| {
            switch (v) {
                .string => |s| std.debug.print("{s}\n", .{s}),
                .null => std.debug.print("(null)\n", .{}),
                else => std.debug.print("{s}\n", .{result.description orelse "(undefined)"}),
            }
        } else {
            std.debug.print("(undefined)\n", .{});
        }
        return;
    }

    // storage local  → list all
    const js = try std.fmt.allocPrint(ctx.allocator,
        \\JSON.stringify(Object.fromEntries(
        \\  Object.keys({s}).map(k => [k, {s}.getItem(k)])
        \\))
    , .{ js_obj, js_obj });
    defer ctx.allocator.free(js);
    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);
    if (result.value) |v| {
        switch (v) {
            .string => |s| {
                if (std.mem.eql(u8, s, "{}")) {
                    std.debug.print("No {s} storage entries\n", .{store_type});
                } else {
                    std.debug.print("{s}\n", .{s});
                }
            },
            else => std.debug.print("No {s} storage entries\n", .{store_type}),
        }
    } else {
        std.debug.print("No {s} storage entries\n", .{store_type});
    }
}

fn jsStringLiteral(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    try result.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }
    try result.append(allocator, '"');
    return result.toOwnedSlice(allocator);
}

fn printStorageUsage() void {
    std.debug.print(
        \\Usage: storage <local|session> [subcommand] [args]
        \\
        \\Subcommands:
        \\  storage local              Get all localStorage entries (JSON)
        \\  storage local <key>        Get specific key
        \\  storage local set <k> <v>  Set value
        \\  storage local clear        Clear all entries
        \\  storage local export <f>   Export to JSON/YAML file
        \\  storage local import <f>   Import from JSON/YAML file
        \\  storage session            Same commands for sessionStorage
        \\
    , .{});
}

pub fn network() void {
    std.debug.print("Network monitoring not yet implemented\n", .{});
}

// ─── Element Actions ────────────────────────────────────────────────────────

pub fn click(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: click <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, ctx.allocator, &resolved, 1);
    std.debug.print("Clicked: {s}\n", .{ctx.positional[0]});
}

pub fn dblclick(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: dblclick <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.clickElement(session, ctx.allocator, &resolved, 2);
    std.debug.print("Double-clicked: {s}\n", .{ctx.positional[0]});
}

pub fn focus(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: focus <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.focusElement(session, ctx.allocator, &resolved);
    std.debug.print("Focused: {s}\n", .{ctx.positional[0]});
}

pub fn typeText(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: type <selector> <text>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.focusElement(session, ctx.allocator, &resolved);
    var j: u32 = 0;
    while (j < 500000) : (j += 1) std.atomic.spinLoopHint();
    try actions_mod.typeText(session, ctx.positional[1]);
    std.debug.print("Typed into: {s}\n", .{ctx.positional[0]});
}

pub fn fill(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: fill <selector> <text>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.fillElement(session, ctx.allocator, &resolved, ctx.positional[1]);
    std.debug.print("Filled: {s}\n", .{ctx.positional[0]});
}

pub fn selectOption(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: select <selector> <value>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.selectOption(session, ctx.allocator, &resolved, ctx.positional[1]);
    std.debug.print("Selected '{s}' in: {s}\n", .{ ctx.positional[1], ctx.positional[0] });
}

pub fn check(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: check <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.setChecked(session, ctx.allocator, &resolved, true);
    std.debug.print("Checked: {s}\n", .{ctx.positional[0]});
}

pub fn uncheck(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: uncheck <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.setChecked(session, ctx.allocator, &resolved, false);
    std.debug.print("Unchecked: {s}\n", .{ctx.positional[0]});
}

pub fn hover(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: hover <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.hoverElement(session, ctx.allocator, &resolved);
    std.debug.print("Hovering: {s}\n", .{ctx.positional[0]});
}

pub fn scroll(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: scroll <up|down|left|right> [pixels]\n", .{});
        return;
    }

    const direction = ctx.positional[0];
    const pixels: f64 = if (ctx.positional.len > 1)
        @floatFromInt(std.fmt.parseInt(i32, ctx.positional[1], 10) catch 300)
    else
        300;

    var delta_x: f64 = 0;
    var delta_y: f64 = 0;

    if (std.mem.eql(u8, direction, "up")) {
        delta_y = -pixels;
    } else if (std.mem.eql(u8, direction, "down")) {
        delta_y = pixels;
    } else if (std.mem.eql(u8, direction, "left")) {
        delta_x = -pixels;
    } else if (std.mem.eql(u8, direction, "right")) {
        delta_x = pixels;
    } else {
        std.debug.print("Invalid direction: {s}. Use up, down, left, or right.\n", .{direction});
        return;
    }

    try actions_mod.scroll(session, delta_x, delta_y);
    std.debug.print("Scrolled {s} {d}px\n", .{ direction, pixels });
}

pub fn scrollIntoView(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: scrollintoview <selector>\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    try actions_mod.scrollIntoView(session, ctx.allocator, &resolved);
    std.debug.print("Scrolled into view: {s}\n", .{ctx.positional[0]});
}

pub fn drag(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: drag <source-selector> <target-selector>\n", .{});
        return;
    }
    var src_resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer src_resolved.deinit();
    var tgt_resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[1]);
    defer tgt_resolved.deinit();
    try actions_mod.dragElement(session, ctx.allocator, &src_resolved, &tgt_resolved);
    std.debug.print("Dragged: {s} -> {s}\n", .{ ctx.positional[0], ctx.positional[1] });
}

pub fn upload(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Usage: upload <selector> <file1> [file2...]\n", .{});
        return;
    }
    var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, ctx.positional[0]);
    defer resolved.deinit();
    const files = ctx.positional[1..];
    try actions_mod.uploadFiles(session, ctx.allocator, ctx.io, &resolved, files);
    std.debug.print("Uploaded {} file(s) to: {s}\n", .{ files.len, ctx.positional[0] });
}

// ─── Keyboard ───────────────────────────────────────────────────────────────

pub fn press(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: press <key>\n", .{});
        std.debug.print("Examples: press Enter, press Tab, press Control+a\n", .{});
        return;
    }
    try actions_mod.pressKey(session, ctx.positional[0]);
    std.debug.print("Pressed: {s}\n", .{ctx.positional[0]});
}

pub fn keyDown(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: keydown <key>\n", .{});
        return;
    }
    try actions_mod.keyDown(session, ctx.positional[0]);
    std.debug.print("Key down: {s}\n", .{ctx.positional[0]});
}

pub fn keyUp(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        std.debug.print("Usage: keyup <key>\n", .{});
        return;
    }
    try actions_mod.keyUp(session, ctx.positional[0]);
    std.debug.print("Key up: {s}\n", .{ctx.positional[0]});
}

// ─── Mouse ──────────────────────────────────────────────────────────────────

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

// ─── Wait ───────────────────────────────────────────────────────────────────

pub fn wait(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag in positional args
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printWaitHelp();
            return;
        }
    }

    const timeout_ms: u32 = 30_000; // default 30s

    if (ctx.wait_text) |text| {
        try waitForText(session, ctx.allocator, text, timeout_ms);
    } else if (ctx.wait_url) |pattern| {
        try waitForUrl(session, ctx.allocator, pattern, timeout_ms);
    } else if (ctx.wait_load) |state| {
        try waitForLoadState(session, ctx.allocator, state, timeout_ms);
    } else if (ctx.wait_fn) |expr| {
        try waitForFunction(session, ctx.allocator, expr, timeout_ms);
    } else if (ctx.positional.len > 0) {
        const arg = ctx.positional[0];
        // Check if it's a number (ms) or selector
        if (std.fmt.parseInt(u32, arg, 10)) |ms| {
            waitForTime(ms);
            std.debug.print("Waited {}ms\n", .{ms});
        } else |_| {
            // Treat as selector
            try waitForSelector(session, ctx.allocator, ctx.io, arg, timeout_ms);
        }
    } else {
        printWaitUsage();
    }
}

fn printWaitUsage() void {
    std.debug.print(
        \\Usage: wait <selector|ms> [options]
        \\
        \\Options:
        \\  --text <string>    Wait for text to appear on page
        \\  --match <pattern>  Wait for URL to match pattern (glob: ** and *)
        \\  --load <state>     Wait for load state (load, domcontentloaded, networkidle)
        \\  --fn <expression>  Wait for JS expression to return truthy
        \\
        \\Examples:
        \\  wait "#login-form"           Wait for element to be visible
        \\  wait 2000                    Wait 2 seconds
        \\  wait --text "Welcome"        Wait for text
        \\  wait --load networkidle      Wait for network idle
        \\
    , .{});
}

fn waitForTime(ms: u32) void {
    // Use spinloop (Zig 0.16 doesn't have std.time.sleep in this context)
    // Empirically calibrated: ~20_000_000 iterations ≈ 1 second
    const iterations_per_second: u64 = 20_000_000;
    const total_iterations: u64 = (@as(u64, ms) * iterations_per_second) / 1000;
    var i: u64 = 0;
    while (i < total_iterations) : (i += 1) {
        std.atomic.spinLoopHint();
    }
}

fn waitForSelector(session: *cdp.Session, allocator: std.mem.Allocator, io: std.Io, selector: []const u8, timeout_ms: u32) !void {
    var resolved = try actions_mod.resolveSelector(allocator, io, selector);
    defer resolved.deinit();

    // Build JS to check element visibility (handles both CSS and role-based)
    const js = try actions_mod.helpers.buildGetterJs(allocator, &resolved, "el && el.offsetParent !== null && getComputedStyle(el).visibility !== 'hidden'");
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        std.debug.print("Element visible: {s}\n", .{selector});
    } else {
        std.debug.print("Timeout waiting for element: {s}\n", .{selector});
        return error.Timeout;
    }
}

fn waitForText(session: *cdp.Session, allocator: std.mem.Allocator, text: []const u8, timeout_ms: u32) !void {
    const escaped = try actions_mod.helpers.escapeJsString(allocator, text);
    defer allocator.free(escaped);

    const js = try std.fmt.allocPrint(allocator, "document.body.innerText.includes('{s}')", .{escaped});
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        std.debug.print("Text found: \"{s}\"\n", .{text});
    } else {
        std.debug.print("Timeout waiting for text: \"{s}\"\n", .{text});
        return error.Timeout;
    }
}

fn waitForUrl(session: *cdp.Session, allocator: std.mem.Allocator, pattern: []const u8, timeout_ms: u32) !void {
    // Convert glob pattern to regex
    const regex_pattern = try globToRegex(allocator, pattern);
    defer allocator.free(regex_pattern);

    const js = try std.fmt.allocPrint(allocator, "new RegExp('{s}').test(window.location.href)", .{regex_pattern});
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        // Get current URL for output
        var runtime = cdp.Runtime.init(session);
        const url = runtime.evaluateAs([]const u8, "window.location.href") catch "unknown";
        std.debug.print("URL matched: {s}\n", .{url});
    } else {
        std.debug.print("Timeout waiting for URL pattern: {s}\n", .{pattern});
        return error.Timeout;
    }
}

fn waitForLoadState(session: *cdp.Session, allocator: std.mem.Allocator, state: []const u8, timeout_ms: u32) !void {
    const js: []const u8 = if (std.mem.eql(u8, state, "load"))
        "document.readyState === 'complete'"
    else if (std.mem.eql(u8, state, "domcontentloaded"))
        "document.readyState !== 'loading'"
    else if (std.mem.eql(u8, state, "networkidle"))
        // Check document complete and no pending fetches
        "document.readyState === 'complete'"
    else {
        std.debug.print("Unknown load state: {s}. Use: load, domcontentloaded, networkidle\n", .{state});
        return error.InvalidLoadState;
    };

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        // For networkidle, add extra wait for network to settle
        if (std.mem.eql(u8, state, "networkidle")) {
            waitForTime(500); // Extra 500ms for network to settle
        }
        std.debug.print("Load state reached: {s}\n", .{state});
    } else {
        std.debug.print("Timeout waiting for load state: {s}\n", .{state});
        return error.Timeout;
    }
}

fn waitForFunction(session: *cdp.Session, allocator: std.mem.Allocator, expr: []const u8, timeout_ms: u32) !void {
    const js = try std.fmt.allocPrint(allocator, "(() => {{ return !!({s}); }})()", .{expr});
    defer allocator.free(js);

    if (try pollUntil(session, allocator, js, timeout_ms)) {
        std.debug.print("Condition satisfied: {s}\n", .{expr});
    } else {
        std.debug.print("Timeout waiting for condition: {s}\n", .{expr});
        return error.Timeout;
    }
}

/// Poll a JS condition until it returns true or timeout
fn pollUntil(session: *cdp.Session, allocator: std.mem.Allocator, js_condition: []const u8, timeout_ms: u32) !bool {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Poll every ~250ms, calculate number of iterations based on timeout
    const poll_interval_ms: u32 = 250;
    const max_polls = (timeout_ms + poll_interval_ms - 1) / poll_interval_ms;
    var poll_count: u32 = 0;

    while (poll_count < max_polls) : (poll_count += 1) {
        var result = try runtime.evaluate(allocator, js_condition, .{ .return_by_value = true });
        defer result.deinit(allocator);

        if (result.asBool()) |b| {
            if (b) return true;
        }

        // Wait between polls
        waitForTime(poll_interval_ms);
    }
    return false;
}

/// Convert glob pattern to regex (** = .*, * = [^/]*)
fn globToRegex(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < pattern.len) {
        const c = pattern[i];
        if (c == '*') {
            if (i + 1 < pattern.len and pattern[i + 1] == '*') {
                // ** matches anything
                try result.appendSlice(allocator, ".*");
                i += 2;
            } else {
                // * matches non-slash
                try result.appendSlice(allocator, "[^/]*");
                i += 1;
            }
        } else if (c == '.' or c == '?' or c == '+' or c == '^' or c == '$' or
            c == '{' or c == '}' or c == '(' or c == ')' or c == '|' or
            c == '[' or c == ']' or c == '\\')
        {
            // Escape regex special chars
            try result.append(allocator, '\\');
            try result.append(allocator, c);
            i += 1;
        } else {
            try result.append(allocator, c);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

// ─── Getters ────────────────────────────────────────────────────────────────

pub fn get(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printGetHelp();
            return;
        }
    }

    if (ctx.positional.len == 0) {
        printGetUsage();
        return;
    }

    const subcommand = ctx.positional[0];

    if (std.mem.eql(u8, subcommand, "title")) {
        const title = try actions_mod.getPageTitle(session, ctx.allocator);
        defer ctx.allocator.free(title);
        std.debug.print("{s}\n", .{title});
        return;
    }

    if (std.mem.eql(u8, subcommand, "url")) {
        const url = try actions_mod.getPageUrl(session, ctx.allocator);
        defer ctx.allocator.free(url);
        std.debug.print("{s}\n", .{url});
        return;
    }

    if (ctx.positional.len < 2) {
        std.debug.print("Error: Missing selector\n", .{});
        printGetUsage();
        return;
    }

    const selector = ctx.positional[1];

    if (std.mem.eql(u8, subcommand, "text")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getText(session, ctx.allocator, &resolved)) |text| {
            defer ctx.allocator.free(text);
            std.debug.print("{s}\n", .{text});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "html")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getHtml(session, ctx.allocator, &resolved)) |html| {
            defer ctx.allocator.free(html);
            std.debug.print("{s}\n", .{html});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "dom")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();

        const js = try actions_mod.helpers.buildGetterJs(ctx.allocator, &resolved, "el.outerHTML");
        defer ctx.allocator.free(js);

        var runtime = cdp.Runtime.init(session);
        try runtime.enable();

        var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
        defer result.deinit(ctx.allocator);

        if (result.asString()) |html| {
            std.debug.print("{s}\n", .{html});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "value")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getValue(session, ctx.allocator, &resolved)) |value| {
            defer ctx.allocator.free(value);
            std.debug.print("{s}\n", .{value});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "attr")) {
        if (ctx.positional.len < 3) {
            std.debug.print("Error: Missing attribute name\nUsage: get attr <selector> <attribute>\n", .{});
            return;
        }
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getAttribute(session, ctx.allocator, &resolved, ctx.positional[2])) |v| {
            defer ctx.allocator.free(v);
            std.debug.print("{s}\n", .{v});
        } else {
            std.debug.print("(null)\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "count")) {
        const count = try actions_mod.getCount(session, ctx.allocator, selector);
        std.debug.print("{}\n", .{count});
    } else if (std.mem.eql(u8, subcommand, "box")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        const pos = actions_mod.getElementPosition(session, ctx.allocator, &resolved) catch {
            std.debug.print("(not found)\n", .{});
            return;
        };
        std.debug.print("x={d:.0} y={d:.0} width={d:.0} height={d:.0}\n", .{ pos.x, pos.y, pos.width, pos.height });
    } else if (std.mem.eql(u8, subcommand, "styles")) {
        var resolved = try actions_mod.resolveSelector(ctx.allocator, ctx.io, selector);
        defer resolved.deinit();
        if (try actions_mod.getStyles(session, ctx.allocator, &resolved)) |styles| {
            defer ctx.allocator.free(styles);
            std.debug.print("{s}\n", .{styles});
        } else {
            std.debug.print("(not found)\n", .{});
        }
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{subcommand});
        printGetUsage();
    }
}

fn printGetUsage() void {
    std.debug.print(
        \\Usage: get <subcommand> [selector] [args]
        \\
        \\Subcommands:
        \\  text <sel>           Get text content
        \\  html <sel>           Get innerHTML
        \\  dom <sel>            Get outerHTML
        \\  value <sel>          Get input value
        \\  attr <sel> <attr>    Get attribute value
        \\  title                Get page title
        \\  url                  Get current URL
        \\  count <sel>          Count matching elements
        \\  box <sel>            Get bounding box
        \\  styles <sel>         Get computed styles (JSON)
        \\
    , .{});
}

// ─── Dispatch ───────────────────────────────────────────────────────────────

/// Dispatch a session-level command. Returns true if handled.
pub fn dispatchSessionCommand(session: *cdp.Session, command: anytype, ctx: CommandCtx) !bool {
    switch (command) {
        .navigate => try navigate(session, ctx),
        .screenshot => try screenshot(session, ctx),
        .pdf => try pdf(session, ctx),
        .evaluate => try evaluate(session, ctx),
        .network => network(),
        .cookies => try cookies(session, ctx),
        .storage => try webStorage(session, ctx),
        .snapshot => try snapshot(session, ctx),
        .click => try click(session, ctx),
        .dblclick => try dblclick(session, ctx),
        .focus => try focus(session, ctx),
        .type => try typeText(session, ctx),
        .fill => try fill(session, ctx),
        .select => try selectOption(session, ctx),
        .hover => try hover(session, ctx),
        .check => try check(session, ctx),
        .uncheck => try uncheck(session, ctx),
        .scroll => try scroll(session, ctx),
        .scrollintoview => try scrollIntoView(session, ctx),
        .drag => try drag(session, ctx),
        .get => try get(session, ctx),
        .upload => try upload(session, ctx),
        .back => try back(session),
        .forward => try forward(session),
        .reload => try reload(session),
        .press => try press(session, ctx),
        .keydown => try keyDown(session, ctx),
        .keyup => try keyUp(session, ctx),
        .wait => try wait(session, ctx),
        .mouse => try mouse(session, ctx),
        else => {
            std.debug.print("Warning: unhandled command in dispatchSessionCommand\n", .{});
            return false;
        },
    }
    return true;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn writeFile(io: std.Io, path: []const u8, data: []const u8) !void {
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{ .sub_path = path, .data = data }) catch |err| {
        std.debug.print("Error writing {s}: {}\n", .{ path, err });
        return err;
    };
}

// ─── Help Functions ────────────────────────────────────────────────────────

pub fn printCookiesHelp() void {
    std.debug.print(
        \\Usage: cookies [subcommand] [args]
        \\
        \\Subcommands:
        \\  cookies                    List all cookies
        \\  cookies <domain>         List cookies for specific domain
        \\  cookies set <name> <value> Set a cookie
        \\  cookies get <name> [domain] Get specific cookie
        \\  cookies delete <name> [domain] Delete specific cookie
        \\  cookies clear [domain]     Clear all cookies (or for domain)
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

pub fn printStorageHelp() void {
    std.debug.print(
        \\Usage: storage <local|session> [subcommand] [args]
        \\
        \\Subcommands:
        \\  storage local              Get all localStorage entries (JSON)
        \\  storage local <key>        Get specific key
        \\  storage local set <k> <v>  Set value
        \\  storage local clear        Clear all entries
        \\  storage local export <f>   Export to JSON/YAML file
        \\  storage local import <f>   Import from JSON/YAML file
        \\  storage session          Same commands for sessionStorage
        \\
        \\Examples:
        \\  storage local set theme dark
        \\  storage local get user_id
        \\  storage local export storage.json
        \\  storage session clear
        \\
    , .{});
}

pub fn printGetHelp() void {
    std.debug.print(
        \\Usage: get <subcommand> [selector] [args]
        \\
        \\Subcommands:
        \\  get title                Get page title
        \\  get url                  Get current URL
        \\  get text <sel>           Get text content
        \\  get html <sel>           Get innerHTML
        \\  get dom <sel>            Get outerHTML
        \\  get value <sel>          Get input value
        \\  get attr <sel> <attr>    Get attribute value
        \\  get count <sel>          Count matching elements
        \\  get box <sel>            Get bounding box (x, y, width, height)
        \\  get styles <sel>         Get computed styles (JSON)
        \\
        \\Examples:
        \\  get title
        \\  get text "#header"
        \\  get attr "#link" href
        \\  get count "li.item"
        \\
    , .{});
}

pub fn printTabHelp() void {
    std.debug.print(
        \\Usage: tab [subcommand] [args]
        \\
        \\Subcommands:
        \\  tab                      List open tabs (numbered)
        \\  tab new [url]            Open new tab (optionally navigate to URL)
        \\  tab <n>                  Switch to tab n
        \\  tab close [n]            Close tab n (default: current)
        \\
        \\Examples:
        \\  tab new https://example.com
        \\  tab 2
        \\  tab close
        \\  tab close 1
        \\
    , .{});
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

pub fn printWaitHelp() void {
    std.debug.print(
        \\Usage: wait <selector|ms> [options]
        \\
        \\Options:
        \\  --text <string>    Wait for text to appear on page
        \\  --match <pattern>  Wait for URL to match pattern (glob: ** and *)
        \\  --load <state>     Wait for load state (load, domcontentloaded, networkidle)
        \\  --fn <expression>  Wait for JS expression to return truthy
        \\
        \\Examples:
        \\  wait "#login-form"           Wait for element to be visible
        \\  wait 2000                    Wait 2 seconds
        \\  wait --text "Welcome"        Wait for text
        \\  wait --match "**/dashboard"   Wait for URL pattern
        \\  wait --load networkidle       Wait for network idle
        \\  wait --fn "window.ready"      Wait for JS condition
        \\
    , .{});
}

pub fn printSnapshotHelp() void {
    std.debug.print(
        \\Usage: snapshot [options]
        \\
        \\Options:
        \\  -i, --interactive-only   Only include interactive elements
        \\  -c, --compact            Compact output (skip empty structural elements)
        \\  -d, --depth <n>          Limit tree depth
        \\  -s, --selector <sel>     Scope snapshot to CSS selector
        \\  --output <path>          Output file path (default: zsnap.json)
        \\
        \\Examples:
        \\  snapshot                       # Snapshot current page
        \\  snapshot -i                    # Interactive elements only
        \\  snapshot -c -d 3               # Compact mode, depth 3
        \\  snapshot -s "#main-content"    # Scope to selector
        \\
    , .{});
}

pub fn printWindowHelp() void {
    std.debug.print(
        \\Usage: window [subcommand]
        \\
        \\Subcommands:
        \\  window new           Open new browser window
        \\
        \\Examples:
        \\  window new           # Open new browser window
        \\
    , .{});
}
