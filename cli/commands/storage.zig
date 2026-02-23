//! Web storage commands (localStorage, sessionStorage).

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const CommandCtx = types.CommandCtx;

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
            try helpers.jsStringLiteral(ctx.allocator, args[1]),
            try helpers.jsStringLiteral(ctx.allocator, args[2]),
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
        try helpers.writeFile(ctx.io, path, output);
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
            const key_lit = try helpers.jsStringLiteral(ctx.allocator, entry.key_ptr.*);
            defer ctx.allocator.free(key_lit);
            const val_lit = try helpers.jsStringLiteral(ctx.allocator, entry.value_ptr.*.string);
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
            try helpers.jsStringLiteral(ctx.allocator, args[0]),
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
