const std = @import("std");
const json = @import("json");
const types = @import("types.zig");

// JavaScript helpers loaded from external files at compile time
pub const FIND_BY_ROLE_JS = @embedFile("../js/find-by-role.js");
pub const FIND_AND_FOCUS_JS = @embedFile("../js/find-and-focus.js");
pub const FIND_AND_FILL_JS = @embedFile("../js/find-and-fill.js");
pub const FIND_AND_SELECT_JS = @embedFile("../js/find-and-select.js");
pub const FIND_AND_CHECK_JS = @embedFile("../js/find-and-check.js");
pub const FIND_AND_SCROLL_JS = @embedFile("../js/find-and-scroll.js");
pub const FIND_AND_CLICK_JS = @embedFile("../js/find-and-click.js");
pub const LAYOUT_JS = @embedFile("../js/layout.js");

/// JavaScript to find element by CSS selector, returns bounding rect
/// Accepts optional root parameter for shadow DOM piercing
pub const FIND_BY_CSS_JS =
    \\(function(selector, root) {
    \\  root = root || document;
    \\  var el = root.querySelector(selector);
    \\  if (!el) return null;
    \\  var rect = el.getBoundingClientRect();
    \\  return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    \\})
;

pub fn escapeJsString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
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

pub fn getFloatFromJson(val: ?json.Value) ?f64 {
    if (val) |v| {
        return switch (v) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }
    return null;
}

/// JavaScript to find element and get property (handles CSS, role-based, and layout path)
/// Supports optional root_expression for shadow DOM piercing
pub fn buildGetterJs(
    allocator: std.mem.Allocator,
    resolved: *const types.ResolvedElement,
    getter_expr: []const u8,
) ![]const u8 {
    const root_expr = resolved.root_expression orelse "document";

    if (resolved.layout_path) |path| {
        const escaped_path = try escapeJsString(allocator, path);
        defer allocator.free(escaped_path);
        // Inline the path resolution logic for getters
        return try std.fmt.allocPrint(allocator,
            \\(function(pathStr){{
            \\  function getVisibleChildren(el){{return Array.from(el.children).filter(function(c){{var r=c.getBoundingClientRect();return r.width>0&&r.height>0}})}}
            \\  if(!pathStr||pathStr===''){{var el=document.body;return {s}}}
            \\  var indices=pathStr.split('/').map(Number);
            \\  var el=document.body;
            \\  for(var i=0;i<indices.length;i++){{var idx=indices[i];var children=getVisibleChildren(el);if(idx>=children.length)return null;el=children[idx]}}
            \\  return {s}
            \\}})({s})
        , .{ getter_expr, getter_expr, escaped_path });
    } else if (resolved.css_selector) |css| {
        const escaped_css = try escapeJsString(allocator, css);
        defer allocator.free(escaped_css);
        return try std.fmt.allocPrint(allocator, "(function(s,root){{root=root||document;var el=root.querySelector(s);if(!el)return null;return {s}}})({s},{s})", .{ getter_expr, escaped_css, root_expr });
    } else {
        const role = resolved.role orelse return error.InvalidSelector;
        const name_arg = if (resolved.name) |n| try escapeJsString(allocator, n) else try allocator.dupe(u8, "null");
        defer allocator.free(name_arg);
        const nth = resolved.nth orelse 0;

        // Build getter using embedded find-by-role logic with getter expression
        // Now accepts root parameter for shadow DOM piercing
        return try std.fmt.allocPrint(allocator,
            \\(function(role,name,nth,root){{
            \\root=root||document;
            \\var IMPLICIT_ROLES={{'link':'a[href]','button':'button,input[type="button"],input[type="submit"],input[type="reset"]','textbox':'input:not([type]),input[type="text"],input[type="email"],input[type="password"],input[type="search"],input[type="tel"],input[type="url"],input[type="number"],textarea,[contenteditable="true"],[contenteditable=""]','checkbox':'input[type="checkbox"]','radio':'input[type="radio"]','combobox':'select','listbox':'select[multiple]','heading':'h1,h2,h3,h4,h5,h6','img':'img','list':'ul,ol','listitem':'li','navigation':'nav','main':'main','form':'form','table':'table','row':'tr','cell':'td','columnheader':'th','spinbutton':'input[type="number"]','switch':'input[type="checkbox"]'}};
            \\function queryAll(r,sel){{var res=Array.from(r.querySelectorAll(sel));r.querySelectorAll('*').forEach(function(e){{if(e.shadowRoot)res=res.concat(queryAll(e.shadowRoot,sel))}});return res}}
            \\function getLabel(e){{var a=e.getAttribute('aria-label');if(a)return a;var p=e.getAttribute('placeholder');if(p)return p;var id=e.id;if(id){{var doc=root.ownerDocument||root;var l=doc.querySelector('label[for="'+id+'"]');if(l)return l.textContent.trim()}}if(e.type==='checkbox'||e.type==='radio'){{var par=e.closest('label');if(par)return par.textContent.trim()}}return e.textContent.trim()}}
            \\var els=queryAll(root,'[role="'+role+'"]');
            \\if(IMPLICIT_ROLES[role]){{var implicit=queryAll(root,IMPLICIT_ROLES[role]).filter(function(e){{return !e.hasAttribute('role')}});els=els.concat(implicit)}}
            \\function matchesName(e,n){{if(getLabel(e)===n)return true;if(e.getAttribute('name')===n)return true;if(e.id===n)return true;return false}}
            \\if(name)els=els.filter(function(e){{return matchesName(e,name)}});
            \\var el=els[nth||0];if(!el)return null;return {s}
            \\}})('{s}',{s},{d},{s})
        , .{ getter_expr, role, name_arg, nth, root_expr });
    }
}
