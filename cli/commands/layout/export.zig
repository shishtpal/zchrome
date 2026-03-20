//! Export subcommands: save, diff

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const cmd_types = @import("../types.zig");
const cmd_helpers = @import("../helpers.zig");
const action_helpers = @import("../../actions/helpers.zig");

pub const CommandCtx = cmd_types.CommandCtx;
const LAYOUT_JS = action_helpers.LAYOUT_JS;

/// save - export layout tree to JSON file
pub fn save(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Error: Missing filename\nUsage: layout save <file.json> [-d <depth>]\n", .{});
        return;
    }

    const filename = ctx.positional[1];
    const depth_arg = if (ctx.snap_depth) |d|
        try std.fmt.allocPrint(ctx.allocator, "{}", .{d})
    else
        try ctx.allocator.dupe(u8, "null");
    defer ctx.allocator.free(depth_arg);

    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('tree-json', null, {s})", .{ LAYOUT_JS, depth_arg });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .string) {
            // Write to file
            cmd_helpers.writeFile(ctx.io, filename, val.string) catch {
                return;
            };
            std.debug.print("Saved layout to {s}\n", .{filename});
            return;
        }
    }
    std.debug.print("(failed to generate layout)\n", .{});
}

/// diff - compare current layout against saved snapshot
pub fn diff(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    if (ctx.positional.len < 2) {
        std.debug.print("Error: Missing filename\nUsage: layout diff <file.json>\n", .{});
        return;
    }

    const filename = ctx.positional[1];

    // Read saved layout from file
    const dir = std.Io.Dir.cwd();
    const saved_json = dir.readFileAlloc(ctx.io, filename, ctx.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };
    defer ctx.allocator.free(saved_json);

    // Escape the JSON for embedding in JS
    const escaped_json = try cmd_helpers.jsStringLiteral(ctx.allocator, saved_json);
    defer ctx.allocator.free(escaped_json);

    // Compare in JS
    const js = try std.fmt.allocPrint(ctx.allocator,
        \\(function(savedJson) {{
        \\  var saved = JSON.parse(savedJson);
        \\  
        \\  function getVisible(el) {{
        \\    return Array.from(el.children).filter(function(c) {{
        \\      var r = c.getBoundingClientRect();
        \\      return r.width > 0 && r.height > 0;
        \\    }});
        \\  }}
        \\  
        \\  function buildCurrent(el, path) {{
        \\    var r = el.getBoundingClientRect();
        \\    var node = {{
        \\      path: path,
        \\      tag: el.tagName.toLowerCase(),
        \\      x: Math.round(r.x), y: Math.round(r.y),
        \\      w: Math.round(r.width), h: Math.round(r.height),
        \\      children: []
        \\    }};
        \\    var ch = getVisible(el);
        \\    for (var i = 0; i < ch.length; i++) {{
        \\      node.children.push(buildCurrent(ch[i], path ? path + '/' + i : String(i)));
        \\    }}
        \\    return node;
        \\  }}
        \\  
        \\  var current = buildCurrent(document.body, '');
        \\  var diffs = [];
        \\  
        \\  function compare(oldNode, newNode, path) {{
        \\    if (!oldNode && newNode) {{
        \\      diffs.push({{ type: '+', path: '@L' + (newNode.path || ''), tag: newNode.tag }});
        \\      return;
        \\    }}
        \\    if (oldNode && !newNode) {{
        \\      diffs.push({{ type: '-', path: '@L' + (oldNode.path || ''), tag: oldNode.tag }});
        \\      return;
        \\    }}
        \\    if (oldNode.tag !== newNode.tag) {{
        \\      diffs.push({{ type: '~', path: '@L' + path, change: 'tag: ' + oldNode.tag + ' -> ' + newNode.tag }});
        \\    }}
        \\    if (oldNode.w !== newNode.w || oldNode.h !== newNode.h) {{
        \\      diffs.push({{ type: '~', path: '@L' + path, change: 'size: ' + oldNode.w + 'x' + oldNode.h + ' -> ' + newNode.w + 'x' + newNode.h }});
        \\    }}
        \\    if (Math.abs(oldNode.x - newNode.x) > 5 || Math.abs(oldNode.y - newNode.y) > 5) {{
        \\      diffs.push({{ type: '~', path: '@L' + path, change: 'pos: (' + oldNode.x + ',' + oldNode.y + ') -> (' + newNode.x + ',' + newNode.y + ')' }});
        \\    }}
        \\    var maxLen = Math.max(oldNode.children.length, newNode.children.length);
        \\    for (var i = 0; i < maxLen; i++) {{
        \\      var childPath = path ? path + '/' + i : String(i);
        \\      compare(oldNode.children[i], newNode.children[i], childPath);
        \\    }}
        \\  }}
        \\  
        \\  compare(saved, current, '');
        \\  return diffs;
        \\}})({s})
    , .{escaped_json});
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .array) {
            if (val.array.items.len == 0) {
                std.debug.print("No differences found\n", .{});
                return;
            }
            for (val.array.items) |item| {
                if (item == .object) {
                    const diff_type = if (item.object.get("type")) |t| (if (t == .string) t.string else "?") else "?";
                    const path = if (item.object.get("path")) |p| (if (p == .string) p.string else "?") else "?";

                    if (std.mem.eql(u8, diff_type, "+")) {
                        const tag = if (item.object.get("tag")) |t| (if (t == .string) t.string else "?") else "?";
                        std.debug.print("+ {s} <{s}> (added)\n", .{ path, tag });
                    } else if (std.mem.eql(u8, diff_type, "-")) {
                        const tag = if (item.object.get("tag")) |t| (if (t == .string) t.string else "?") else "?";
                        std.debug.print("- {s} <{s}> (removed)\n", .{ path, tag });
                    } else if (std.mem.eql(u8, diff_type, "~")) {
                        const change = if (item.object.get("change")) |c| (if (c == .string) c.string else "?") else "?";
                        std.debug.print("~ {s} {s}\n", .{ path, change });
                    }
                }
            }
            return;
        }
    }
    std.debug.print("(diff failed)\n", .{});
}
