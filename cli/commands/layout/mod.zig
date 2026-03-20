//! Layout command - display DOM as a tree of bounding boxes.
//! Useful for understanding page structure and generating @L paths.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const cmd_types = @import("../types.zig");
const cmd_helpers = @import("../helpers.zig");
const action_helpers = @import("../../actions/helpers.zig");

// Submodules
const navigation = @import("navigation.zig");
const conversion = @import("conversion.zig");
const search = @import("search.zig");
const export_mod = @import("export.zig");
const visual = @import("visual.zig");
const tree_mod = @import("tree.zig");
const layout_types = @import("types.zig");

pub const CommandCtx = cmd_types.CommandCtx;
const LAYOUT_JS = action_helpers.LAYOUT_JS;

/// Layout command: display DOM structure as bounding box tree
pub fn layout(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --json flag
    var json_output = false;
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        }
    }

    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Handle subcommands
    if (ctx.positional.len > 0) {
        const subcmd = ctx.positional[0];

        // xpath/css - convert to layout path
        if (std.mem.eql(u8, subcmd, "xpath")) {
            try conversion.selectorToLayout(&runtime, ctx, true);
            return;
        }
        if (std.mem.eql(u8, subcmd, "css")) {
            try conversion.selectorToLayout(&runtime, ctx, false);
            return;
        }

        // exists - check if path is valid
        if (std.mem.eql(u8, subcmd, "exists")) {
            try navigation.exists(&runtime, ctx);
            return;
        }

        // parent - get parent path
        if (std.mem.eql(u8, subcmd, "parent")) {
            try navigation.parent(&runtime, ctx);
            return;
        }

        // next/prev - get sibling path
        if (std.mem.eql(u8, subcmd, "next")) {
            try navigation.sibling(&runtime, ctx, "next");
            return;
        }
        if (std.mem.eql(u8, subcmd, "prev")) {
            try navigation.sibling(&runtime, ctx, "prev");
            return;
        }

        // children - list child paths
        if (std.mem.eql(u8, subcmd, "children")) {
            try navigation.children(&runtime, ctx);
            return;
        }

        // tocss - generate CSS selector
        if (std.mem.eql(u8, subcmd, "tocss")) {
            try conversion.toCss(&runtime, ctx);
            return;
        }

        // find - search by text
        if (std.mem.eql(u8, subcmd, "find")) {
            try search.find(&runtime, ctx);
            return;
        }

        // at - lookup by coordinates
        if (std.mem.eql(u8, subcmd, "at")) {
            try search.at(&runtime, ctx);
            return;
        }

        // save - export layout tree to JSON file
        if (std.mem.eql(u8, subcmd, "save")) {
            try export_mod.save(&runtime, ctx);
            return;
        }

        // diff - compare current layout against saved snapshot
        if (std.mem.eql(u8, subcmd, "diff")) {
            try export_mod.diff(&runtime, ctx);
            return;
        }

        // screenshot - take screenshot with @L annotations
        if (std.mem.eql(u8, subcmd, "screenshot")) {
            try visual.screenshot(session, &runtime, ctx);
            return;
        }

        // highlight - show visual overlay with @L paths
        if (std.mem.eql(u8, subcmd, "highlight")) {
            try visual.highlight(&runtime, ctx);
            return;
        }

        // pick - interactive element selection
        if (std.mem.eql(u8, subcmd, "pick")) {
            try visual.pick(&runtime, ctx);
            return;
        }
    }

    // Default: display layout tree
    const selector_arg = if (ctx.snap_selector) |s|
        try cmd_helpers.jsStringLiteral(ctx.allocator, s)
    else
        try ctx.allocator.dupe(u8, "null");
    defer ctx.allocator.free(selector_arg);

    const depth_arg = if (ctx.snap_depth) |d|
        try std.fmt.allocPrint(ctx.allocator, "{}", .{d})
    else
        try ctx.allocator.dupe(u8, "null");
    defer ctx.allocator.free(depth_arg);

    const action = if (json_output) "tree-json" else "tree";
    const js = try std.fmt.allocPrint(ctx.allocator, "{s}('{s}', {s}, {s})", .{ LAYOUT_JS, action, selector_arg, depth_arg });
    defer ctx.allocator.free(js);

    var result = try runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true });
    defer result.deinit(ctx.allocator);

    // JSON output mode - return string directly
    if (json_output) {
        if (result.asString()) |json_str| {
            std.debug.print("{s}\n", .{json_str});
            return;
        }
        std.debug.print("Error: Could not extract layout tree\n", .{});
        return;
    }

    // Formatted tree output
    if (result.value) |val| {
        if (val == .object) {
            var root = try tree_mod.parseLayoutNode(ctx.allocator, val);
            defer root.deinit(ctx.allocator);

            std.debug.print("Layout tree\n", .{});
            tree_mod.printLayoutTree(&root, 0);
            std.debug.print("\nUse @L<path> in commands, e.g.: click @L0/2/1\n", .{});
            return;
        }
    }

    std.debug.print("Error: Could not extract layout tree\n", .{});
}

pub fn printLayoutHelp() void {
    std.debug.print(
        \\Usage: layout [subcommand] [options]
        \\
        \\Display DOM structure as a tree of bounding boxes.
        \\Each element shows its path, dimensions, position, and tag.
        \\
        \\Subcommands:
        \\  xpath <xpath>            Convert XPath to layout selector
        \\  css <selector>           Convert CSS selector to layout selector
        \\  tocss @L<path>           Convert layout path to CSS selector
        \\  exists @L<path>          Check if path is valid (true/false)
        \\  parent @L<path>          Get parent path
        \\  next @L<path>            Get next sibling path
        \\  prev @L<path>            Get previous sibling path
        \\  children [@L<path>]      List child paths (default: body)
        \\  find <text>              Search for elements containing text
        \\  at <x> <y>               Find element at screen coordinates
        \\  save <file.json>         Export layout tree to JSON file
        \\  diff <file.json>         Compare current layout against saved snapshot
        \\  screenshot               Take screenshot with @L annotations
        \\  highlight [options]      Show visual overlay with @L paths
        \\  pick                     Click on element to get its @L path
        \\
        \\Tree Options:
        \\  -s, --selector <sel>     Scope tree to CSS selector (default: body)
        \\  -d, --depth <n>          Limit tree depth (also max depth for highlight)
        \\  --json                   Output raw JSON instead of formatted tree
        \\
        \\Highlight Options:
        \\  @L<path>                 Start from specific element (default: body)
        \\  -f, --from <n>           Start highlighting from depth n (default: 0)
        \\  -d <n>                   Highlight up to depth n (default: from+2)
        \\  -t, --time <sec>         Timeout in seconds (default: 5)
        \\
        \\Examples:
        \\  layout                       # Full page layout tree
        \\  layout -s "#main"            # Layout of #main element
        \\  layout -d 3                  # Limit to 3 levels deep
        \\  layout --json                # Output as JSON
        \\  layout xpath "/html/body/div[1]/h1"   # Convert XPath to @L path
        \\  layout css "#main > .header"          # Convert CSS to @L path
        \\  layout tocss @L0/1/2         # Output: body > :nth-child(1) > ...
        \\  layout exists @L0/5          # Check if element exists
        \\  layout parent @L0/1/2        # Output: @L0/1
        \\  layout next @L0/1            # Output: @L0/2
        \\  layout children @L0          # List all children of @L0
        \\  layout find "Submit"         # Find elements with "Submit" text
        \\  layout at 400 200            # Find element at coordinates
        \\  layout highlight             # Highlight depth 0-2 (5s timeout)
        \\  layout highlight -f 3 -d 5   # Highlight depth 3 to 5 only
        \\  layout highlight -t 10       # 10 second timeout
        \\  layout highlight @L0/1       # Highlight subtree at @L0/1
        \\  layout pick                  # Interactive element picker
        \\  layout save before.json      # Save layout to file
        \\  layout diff before.json      # Compare with saved layout
        \\  layout screenshot            # Screenshot with @L annotations
        \\  layout screenshot -d 3 -o out.png  # Custom depth and output
        \\
        \\Output format:
        \\  [@L0] 800x100 @ (0,0) <div#main.container>
        \\    [@L0/0] 800x30 @ (0,0) <h1> "Welcome to..."
        \\    [@L0/1] 80x20 @ (10,50) <a.link> "Click here"
        \\
        \\  Elements show: path, size, position, tag, #id, .class, "text"
        \\
        \\Use @L<path> as selector in other commands:
        \\  click @L0/2/1               # Click element at path
        \\  get @L0/1 text              # Get text content
        \\  snapshot -s @L1             # Snapshot scoped to element
        \\
    , .{});
}
