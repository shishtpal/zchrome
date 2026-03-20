//! Visual subcommands: screenshot, highlight, pick

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const cmd_types = @import("../types.zig");
const cmd_helpers = @import("../helpers.zig");
const layout_types = @import("types.zig");
const action_helpers = @import("../../actions/helpers.zig");

pub const CommandCtx = cmd_types.CommandCtx;
const LAYOUT_JS = action_helpers.LAYOUT_JS;

/// screenshot - take screenshot with @L annotations
pub fn screenshot(session: *cdp.Session, runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    const max_depth: i32 = if (ctx.snap_depth) |d| @intCast(d) else 2;
    const output_path = ctx.output orelse "layout.png";

    // Draw highlights (no auto-removal timeout)
    const draw_js = try std.fmt.allocPrint(ctx.allocator,
        \\(function(maxDepth) {{
        \\  document.querySelectorAll('.__zc_hl').forEach(function(e) {{ e.remove(); }});
        \\  var colors = ['66,133,244', '234,67,53', '52,168,83', '251,188,5'];
        \\  var count = 0;
        \\  function getVisible(el) {{
        \\    return Array.from(el.children).filter(function(c) {{
        \\      var r = c.getBoundingClientRect();
        \\      return r.width > 0 && r.height > 0;
        \\    }});
        \\  }}
        \\  function highlight(el, path, depth) {{
        \\    if (depth > maxDepth) return;
        \\    var r = el.getBoundingClientRect();
        \\    if (r.width <= 0 || r.height <= 0) return;
        \\    var c = colors[depth % 4];
        \\    var div = document.createElement('div');
        \\    div.className = '__zc_hl';
        \\    div.style.cssText = 'position:fixed;left:'+r.left+'px;top:'+r.top+'px;width:'+r.width+'px;height:'+r.height+'px;background:rgba('+c+',0.15);border:2px solid rgb('+c+');pointer-events:none;z-index:'+(2147483640-depth)+';box-sizing:border-box;';
        \\    var lbl = document.createElement('span');
        \\    lbl.style.cssText = 'position:absolute;top:0;left:0;background:rgb('+c+');color:white;font:bold 9px monospace;padding:1px 3px;white-space:nowrap;';
        \\    lbl.textContent = '@L' + (path || '');
        \\    div.appendChild(lbl);
        \\    document.body.appendChild(div);
        \\    count++;
        \\    var ch = getVisible(el);
        \\    for (var i = 0; i < ch.length; i++) {{
        \\      highlight(ch[i], path ? (path + '/' + i) : String(i), depth + 1);
        \\    }}
        \\  }}
        \\  highlight(document.body, '', 0);
        \\  return count;
        \\}})({d})
    , .{max_depth});
    defer ctx.allocator.free(draw_js);

    var draw_result = try runtime.evaluate(ctx.allocator, draw_js, .{ .return_by_value = true });
    defer draw_result.deinit(ctx.allocator);

    // Take screenshot
    var page = cdp.Page.init(session);
    const screenshot_data = try page.captureScreenshot(ctx.allocator, .{ .format = .png });
    defer ctx.allocator.free(screenshot_data);

    // Remove highlights
    const remove_js = "document.querySelectorAll('.__zc_hl').forEach(function(e) { e.remove(); })";
    var remove_result = try runtime.evaluate(ctx.allocator, remove_js, .{});
    defer remove_result.deinit(ctx.allocator);

    // Decode and save
    const decoded = try cdp.base64.decodeAlloc(ctx.allocator, screenshot_data);
    defer ctx.allocator.free(decoded);

    try cmd_helpers.writeFile(ctx.io, output_path, decoded);

    const count = if (draw_result.value) |v| (if (v == .integer) v.integer else 0) else 0;
    std.debug.print("Saved annotated screenshot to {s} ({} elements, depth 0-{d})\n", .{ output_path, count, max_depth });
}

/// highlight - show visual overlay with @L paths
pub fn highlight(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    var path: []const u8 = "";
    var timeout_ms: i32 = 5000; // default 5 seconds
    var min_depth: i32 = 0; // start highlighting from this depth
    var max_depth_override: ?i32 = null;

    // Parse args: highlight [@L<path>] [-t <seconds>] [-f <from>] [-d <to>]
    var i: usize = 1;
    while (i < ctx.positional.len) : (i += 1) {
        const arg = ctx.positional[i];
        if ((std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--time")) and i + 1 < ctx.positional.len) {
            i += 1;
            if (std.fmt.parseInt(i32, ctx.positional[i], 10)) |secs| {
                timeout_ms = secs * 1000;
            } else |_| {}
        } else if ((std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--from")) and i + 1 < ctx.positional.len) {
            i += 1;
            if (std.fmt.parseInt(i32, ctx.positional[i], 10)) |d| {
                min_depth = d;
            } else |_| {}
        } else if (std.mem.eql(u8, arg, "-d") and i + 1 < ctx.positional.len) {
            i += 1;
            if (std.fmt.parseInt(i32, ctx.positional[i], 10)) |d| {
                max_depth_override = d;
            } else |_| {}
        } else if (arg.len > 0 and arg[0] == '@') {
            path = layout_types.extractLayoutPath(arg);
        }
    }

    const escaped_path = try cmd_helpers.jsStringLiteral(ctx.allocator, path);
    defer ctx.allocator.free(escaped_path);

    // Use -d if specified, otherwise default to min_depth + 2
    const max_depth: i32 = max_depth_override orelse (if (ctx.snap_depth) |d| @intCast(d) else min_depth + 2);

    const js = try std.fmt.allocPrint(ctx.allocator,
        \\(function(startPath, minDepth, maxDepth, timeoutMs) {{
        \\  // Remove old highlights
        \\  document.querySelectorAll('.__zc_hl').forEach(function(e) {{ e.remove(); }});
        \\  
        \\  var colors = ['66,133,244', '234,67,53', '52,168,83', '251,188,5'];
        \\  var count = 0;
        \\  
        \\  function getVisible(el) {{
        \\    return Array.from(el.children).filter(function(c) {{
        \\      var r = c.getBoundingClientRect();
        \\      return r.width > 0 && r.height > 0;
        \\    }});
        \\  }}
        \\  
        \\  function resolve(p) {{
        \\    if (!p || p === '') return document.body;
        \\    var parts = p.split('/').map(Number);
        \\    var el = document.body;
        \\    for (var i = 0; i < parts.length; i++) {{
        \\      var ch = getVisible(el);
        \\      if (parts[i] >= ch.length) return null;
        \\      el = ch[parts[i]];
        \\    }}
        \\    return el;
        \\  }}
        \\  
        \\  function highlight(el, path, depth) {{
        \\    if (depth > maxDepth) return;
        \\    var r = el.getBoundingClientRect();
        \\    if (r.width <= 0 || r.height <= 0) return;
        \\    
        \\    // Only draw highlight if within depth range
        \\    if (depth >= minDepth) {{
        \\      var c = colors[depth % 4];
        \\      var div = document.createElement('div');
        \\      div.className = '__zc_hl';
        \\      div.style.cssText = 'position:fixed;left:'+r.left+'px;top:'+r.top+'px;width:'+r.width+'px;height:'+r.height+'px;background:rgba('+c+',0.15);border:2px solid rgb('+c+');pointer-events:none;z-index:'+(2147483640-depth)+';box-sizing:border-box;';
        \\      
        \\      var lbl = document.createElement('span');
        \\      lbl.style.cssText = 'position:absolute;top:0;left:0;background:rgb('+c+');color:white;font:bold 9px monospace;padding:1px 3px;white-space:nowrap;';
        \\      lbl.textContent = '@L' + (path || '');
        \\      div.appendChild(lbl);
        \\      document.body.appendChild(div);
        \\      count++;
        \\    }}
        \\    
        \\    var children = getVisible(el);
        \\    for (var i = 0; i < children.length; i++) {{
        \\      var childPath = path ? (path + '/' + i) : String(i);
        \\      highlight(children[i], childPath, depth + 1);
        \\    }}
        \\  }}
        \\  
        \\  var root = resolve(startPath);
        \\  if (!root) return 'Element not found: @L' + startPath;
        \\  
        \\  var startDepth = startPath ? startPath.split('/').length : 0;
        \\  highlight(root, startPath, startDepth);
        \\  
        \\  setTimeout(function() {{
        \\    document.querySelectorAll('.__zc_hl').forEach(function(e) {{ e.remove(); }});
        \\  }}, timeoutMs);
        \\  
        \\  return 'Highlighted ' + count + ' elements (depth ' + minDepth + '-' + maxDepth + ', ' + (timeoutMs/1000) + 's timeout)';
        \\}})({s}, {d}, {d}, {d})
    , .{ escaped_path, min_depth, max_depth, timeout_ms });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .string) {
            std.debug.print("{s}\n", .{val.string});
            return;
        }
    }
    std.debug.print("Highlight applied\n", .{});
}

/// pick - interactive element selection
pub fn pick(runtime: *cdp.Runtime, ctx: CommandCtx) !void {
    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('pick', null, null)", .{LAYOUT_JS});
    defer ctx.allocator.free(js);

    std.debug.print("Click on an element (ESC to cancel)...\n", .{});

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true, .await_promise = true });
    defer result.deinit(ctx.allocator);

    if (result.value) |val| {
        if (val == .object) {
            // Check for cancelled
            if (val.object.get("cancelled")) |c| {
                if (c == .bool and c.bool) {
                    std.debug.print("(cancelled)\n", .{});
                    return;
                }
            }
            // Check for error
            if (val.object.get("error")) |e| {
                if (e == .string) {
                    std.debug.print("Error: {s}\n", .{e.string});
                    return;
                }
            }
            // Success - print element info
            const selector = layout_types.getJsonString(val, "selector");
            const tag = layout_types.getJsonString(val, "tag");
            const id = layout_types.getJsonString(val, "id");
            const cls = layout_types.getJsonString(val, "cls");
            const text = layout_types.getJsonString(val, "text");

            // Format: @L0/1 <button#id.class> "text"
            std.debug.print("{s} ", .{selector});
            layout_types.formatElementTag(tag, id, cls);
            if (text.len > 0) std.debug.print(" \"{s}\"", .{text});
            std.debug.print("\n", .{});
            return;
        }
    }
    std.debug.print("(pick failed)\n", .{});
}
