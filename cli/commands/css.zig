//! CSS inspection and modification commands.
//!
//! Provides access to the CSS domain for stylesheet manipulation,
//! computed style inspection, and CSS injection.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const CommandCtx = types.CommandCtx;

pub fn css(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printCssHelp();
            return;
        }
    }

    const args = ctx.positional;

    if (args.len == 0) {
        printCssUsage();
        return;
    }

    if (std.mem.eql(u8, args[0], "list")) {
        try listCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "get")) {
        try getCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "set")) {
        try setCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "computed")) {
        try computedCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "inject")) {
        try injectCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "pseudo")) {
        try pseudoCmd(session, ctx);
    } else {
        std.debug.print("Unknown css subcommand: {s}\n", .{args[0]});
        printCssUsage();
    }
}

// ─── list ───────────────────────────────────────────────────────────────────

fn listCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    // Use JavaScript to get stylesheet information
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const js =
        \\(function() {
        \\  const result = { external: [], inline: [] };
        \\  
        \\  // Get all stylesheets from document.styleSheets
        \\  for (let i = 0; i < document.styleSheets.length; i++) {
        \\    const sheet = document.styleSheets[i];
        \\    if (sheet.href) {
        \\      result.external.push({
        \\        index: i,
        \\        href: sheet.href,
        \\        disabled: sheet.disabled,
        \\        media: sheet.media.mediaText || 'all'
        \\      });
        \\    } else {
        \\      result.inline.push({
        \\        index: i,
        \\        rules: sheet.cssRules ? sheet.cssRules.length : 0,
        \\        disabled: sheet.disabled
        \\      });
        \\    }
        \\  }
        \\  return JSON.stringify(result);
        \\})()
    ;

    var remote_obj = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch |err| {
        std.debug.print("Error getting stylesheets: {}\n", .{err});
        return;
    };
    defer remote_obj.deinit(ctx.allocator);

    const result_str = if (remote_obj.value) |v| v.asString() orelse null else null;
    if (result_str == null) {
        std.debug.print("Error: No stylesheet data returned\n", .{});
        return;
    }

    // Parse JSON result
    var parsed = json.parse(ctx.allocator, result_str.?, .{}) catch {
        std.debug.print("Error parsing stylesheet info\n", .{});
        return;
    };
    defer parsed.deinit(ctx.allocator);

    std.debug.print("Stylesheets\n", .{});
    std.debug.print("===========\n\n", .{});

    // External stylesheets
    if (parsed.get("external")) |external| {
        if (external.asArray()) |arr| {
            if (arr.len > 0) {
                std.debug.print("External ({}):\n", .{arr.len});
                for (arr) |sheet| {
                    const href = sheet.get("href").?.asString() orelse "(unknown)";
                    const idx = switch (sheet.get("index").?) {
                        .integer => |i| i,
                        .float => |f| @as(i64, @intFromFloat(f)),
                        else => 0,
                    };
                    const disabled = if (sheet.get("disabled")) |d| d.bool else false;
                    const status = if (disabled) " [disabled]" else "";
                    std.debug.print("  [{}] {s}{s}\n", .{ idx, href, status });
                }
                std.debug.print("\n", .{});
            }
        }
    }

    // Inline stylesheets
    if (parsed.get("inline")) |inline_sheets| {
        if (inline_sheets.asArray()) |arr| {
            if (arr.len > 0) {
                std.debug.print("Inline ({}):\n", .{arr.len});
                for (arr) |sheet| {
                    const idx = switch (sheet.get("index").?) {
                        .integer => |i| i,
                        .float => |f| @as(i64, @intFromFloat(f)),
                        else => 0,
                    };
                    const rules = switch (sheet.get("rules").?) {
                        .integer => |i| i,
                        .float => |f| @as(i64, @intFromFloat(f)),
                        else => 0,
                    };
                    const disabled = if (sheet.get("disabled")) |d| d.bool else false;
                    const status = if (disabled) " [disabled]" else "";
                    std.debug.print("  [{}] <style> ({} rules){s}\n", .{ idx, rules, status });
                }
                std.debug.print("\n", .{});
            }
        }
    }

    std.debug.print("Tip: Use 'css computed <selector>' to inspect element styles.\n", .{});
}

// ─── get ────────────────────────────────────────────────────────────────────

fn getCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 2) {
        std.debug.print("Usage: css get <index>\n", .{});
        std.debug.print("  Get stylesheet content by index (from 'css list')\n", .{});
        return;
    }

    const index = std.fmt.parseInt(usize, args[1], 10) catch {
        std.debug.print("Invalid index: {s}\n", .{args[1]});
        return;
    };

    // Use JavaScript to get stylesheet content
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Build JS to get cssText from stylesheet at index
    var js_buf: [512]u8 = undefined;
    const js = std.fmt.bufPrint(&js_buf,
        \\(function() {{
        \\  const sheet = document.styleSheets[{d}];
        \\  if (!sheet) return JSON.stringify({{ error: 'Stylesheet not found' }});
        \\  try {{
        \\    let css = '';
        \\    for (let i = 0; i < sheet.cssRules.length; i++) {{
        \\      css += sheet.cssRules[i].cssText + '\\n';
        \\    }}
        \\    return JSON.stringify({{ css: css, href: sheet.href || null }});
        \\  }} catch(e) {{
        \\    return JSON.stringify({{ error: 'Cannot access stylesheet (CORS): ' + (sheet.href || 'inline') }});
        \\  }}
        \\}})()
    , .{index}) catch {
        std.debug.print("Error building JS\n", .{});
        return;
    };

    var remote_obj = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch |err| {
        std.debug.print("Error getting stylesheet: {}\n", .{err});
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
            std.debug.print("Error: {s}\n", .{err_msg});
            return;
        }
    }

    // Get CSS content
    const css_content = if (parsed.get("css")) |v| v.asString() orelse "" else "";

    if (ctx.output) |output_path| {
        try helpers.writeFile(ctx.io, output_path, css_content);
        std.debug.print("Stylesheet saved to: {s}\n", .{output_path});
    } else {
        if (parsed.get("href")) |href_val| {
            if (href_val.asString()) |href| {
                std.debug.print("/* Source: {s} */\n\n", .{href});
            }
        }
        std.debug.print("{s}\n", .{css_content});
    }
}

// ─── set ────────────────────────────────────────────────────────────────────

fn setCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 3) {
        std.debug.print("Usage: css set <styleSheetId> <file>\n", .{});
        return;
    }

    const style_sheet_id = args[1];
    const file_path = args[2];

    // Read file content
    const dir = std.Io.Dir.cwd();
    const content = dir.readFileAlloc(ctx.io, file_path, ctx.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
        std.debug.print("Error reading file '{s}': {}\n", .{ file_path, err });
        return;
    };
    defer ctx.allocator.free(content);

    // CSS domain requires DOM to be enabled first
    var dom = cdp.DOM.init(session);
    try dom.enable();

    var css_domain = cdp.CSS.init(session);
    try css_domain.enable();

    const source_map_url = try css_domain.setStyleSheetText(ctx.allocator, style_sheet_id, content);
    defer ctx.allocator.free(source_map_url);

    std.debug.print("Stylesheet updated: {s}\n", .{style_sheet_id});
    if (source_map_url.len > 0) {
        std.debug.print("Source map URL: {s}\n", .{source_map_url});
    }
}

// ─── computed ───────────────────────────────────────────────────────────────

fn computedCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 2) {
        std.debug.print("Usage: css computed <selector>\n", .{});
        return;
    }

    const selector = args[1];

    // Get node ID for the selector
    var dom = cdp.DOM.init(session);
    try dom.enable();
    const doc = try dom.getDocument(ctx.allocator, .{});
    defer {
        var d = doc;
        d.deinit(ctx.allocator);
    }

    const node_id = dom.querySelector(doc.node_id, selector) catch |err| {
        std.debug.print("Element not found: {s} ({})\n", .{ selector, err });
        return;
    };

    var css_domain = cdp.CSS.init(session);
    try css_domain.enable();

    const props = try css_domain.getComputedStyleForNode(ctx.allocator, node_id);
    defer {
        for (props) |*p| p.deinit(ctx.allocator);
        ctx.allocator.free(props);
    }

    std.debug.print("Computed styles for '{s}':\n", .{selector});
    for (props) |prop| {
        // Skip empty or default values
        if (prop.value.len > 0 and !std.mem.eql(u8, prop.value, "none") and !std.mem.eql(u8, prop.value, "auto") and !std.mem.eql(u8, prop.value, "normal")) {
            std.debug.print("  {s}: {s}\n", .{ prop.name, prop.value });
        }
    }
}

// ─── inject ─────────────────────────────────────────────────────────────────

fn injectCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 2) {
        std.debug.print("Usage: css inject <css-text>\n", .{});
        std.debug.print("Example: css inject \"body {{ background: red; }}\"\n", .{});
        return;
    }

    // Combine remaining args as CSS text (allows spaces without quoting)
    var css_text_parts: std.ArrayList(u8) = .empty;
    defer css_text_parts.deinit(ctx.allocator);

    for (args[1..], 0..) |arg, i| {
        if (i > 0) try css_text_parts.append(ctx.allocator, ' ');
        try css_text_parts.appendSlice(ctx.allocator, arg);
    }
    const css_text = css_text_parts.items;

    // Get main frame ID
    var page = cdp.Page.init(session);
    try page.enable();
    const frame = try page.getMainFrame(ctx.allocator);
    defer {
        var f = frame;
        f.deinit(ctx.allocator);
    }

    // CSS domain requires DOM to be enabled first
    var dom = cdp.DOM.init(session);
    try dom.enable();

    var css_domain = cdp.CSS.init(session);
    try css_domain.enable();

    // Create a new stylesheet and add the CSS
    const style_sheet_id = try css_domain.createStyleSheet(ctx.allocator, frame.id);
    defer ctx.allocator.free(style_sheet_id);

    _ = try css_domain.setStyleSheetText(ctx.allocator, style_sheet_id, css_text);

    std.debug.print("CSS injected (styleSheetId: {s})\n", .{style_sheet_id});
}

// ─── pseudo ─────────────────────────────────────────────────────────────────

fn pseudoCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    const args = ctx.positional;
    if (args.len < 3) {
        std.debug.print("Usage: css pseudo <selector> <states...>\n", .{});
        std.debug.print("States: hover, active, focus, focus-within, focus-visible, target\n", .{});
        std.debug.print("Example: css pseudo \"button\" hover active\n", .{});
        return;
    }

    const selector = args[1];
    const states = args[2..];

    // Get node ID for the selector
    var dom = cdp.DOM.init(session);
    try dom.enable();
    const doc = try dom.getDocument(ctx.allocator, .{});
    defer {
        var d = doc;
        d.deinit(ctx.allocator);
    }

    const node_id = dom.querySelector(doc.node_id, selector) catch |err| {
        std.debug.print("Element not found: {s} ({})\n", .{ selector, err });
        return;
    };

    var css_domain = cdp.CSS.init(session);
    try css_domain.enable();

    try css_domain.forcePseudoState(node_id, states);

    std.debug.print("Forced pseudo states on '{s}': ", .{selector});
    for (states, 0..) |state, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print(":{s}", .{state});
    }
    std.debug.print("\n", .{});
}

// ─── Help ───────────────────────────────────────────────────────────────────

fn printCssUsage() void {
    std.debug.print("Usage: css <subcommand> [options]\n", .{});
    std.debug.print("\nSubcommands: list, get, set, computed, inject, pseudo\n", .{});
    std.debug.print("Use 'css --help' for details.\n", .{});
}

pub fn printCssHelp() void {
    const help =
        \\CSS Commands
        \\============
        \\
        \\Inspect and modify stylesheets in the browser.
        \\
        \\USAGE:
        \\  css <subcommand> [options]
        \\
        \\SUBCOMMANDS:
        \\  list                      List all stylesheets on the page
        \\  get <index> [-o file]     Get stylesheet content by index
        \\  computed <selector>       Get computed styles for an element
        \\  inject <css-text>         Inject CSS into the page
        \\  pseudo <selector> <states>  Force pseudo states (:hover, :active, :focus)
        \\
        \\EXAMPLES:
        \\  css list                              # List stylesheets
        \\  css get 0                             # Print first stylesheet
        \\  css get 1 -o styles.css               # Save second stylesheet to file
        \\  css computed "button.primary"         # Get computed styles
        \\  css inject "body { background: red; }"
        \\  css pseudo "a.link" hover active
        \\
    ;
    std.debug.print("{s}", .{help});
}
