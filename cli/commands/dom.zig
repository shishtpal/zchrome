//! DOM extraction command - extract DOM structure as JSON.

const std = @import("std");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");

pub const CommandCtx = types.CommandCtx;

/// Extraction modes
pub const ExtractMode = enum {
    dom, // Full DOM tree structure
    text, // Text content only
    html, // Raw innerHTML
    attrs, // Attributes only
    table, // Table to array of objects
    form, // Form field values
    links, // Extract all links (<a href>)
    images, // Extract all images (<img>)

    pub fn fromString(s: []const u8) ?ExtractMode {
        if (std.mem.eql(u8, s, "dom")) return .dom;
        if (std.mem.eql(u8, s, "text")) return .text;
        if (std.mem.eql(u8, s, "html")) return .html;
        if (std.mem.eql(u8, s, "attrs")) return .attrs;
        if (std.mem.eql(u8, s, "table")) return .table;
        if (std.mem.eql(u8, s, "form")) return .form;
        if (std.mem.eql(u8, s, "links")) return .links;
        if (std.mem.eql(u8, s, "images")) return .images;
        return null;
    }

    pub fn toString(self: ExtractMode) []const u8 {
        return switch (self) {
            .dom => "dom",
            .text => "text",
            .html => "html",
            .attrs => "attrs",
            .table => "table",
            .form => "form",
            .links => "links",
            .images => "images",
        };
    }
};

/// JavaScript extraction functions embedded as string
const extract_js =
    \\(function(selector, mode, all) {
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  // DOM to JSON (full tree)
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  function domToJson(node) {
    \\    if (!node) return null;
    \\    
    \\    if (node.nodeType === Node.TEXT_NODE) {
    \\      var text = node.nodeValue.trim();
    \\      return text.length > 0 ? text : null;
    \\    }
    \\    
    \\    if (node.nodeType === Node.COMMENT_NODE) {
    \\      return null;
    \\    }
    \\    
    \\    if (node.nodeType !== Node.ELEMENT_NODE && 
    \\        node.nodeType !== Node.DOCUMENT_NODE &&
    \\        node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE) {
    \\      return null;
    \\    }
    \\    
    \\    var result = {};
    \\    
    \\    if (node.tagName) {
    \\      result.tag = node.tagName.toLowerCase();
    \\    }
    \\    
    \\    // Extract attributes (skip style)
    \\    if (node.attributes && node.attributes.length > 0) {
    \\      var attrs = {};
    \\      var hasAttrs = false;
    \\      for (var i = 0; i < node.attributes.length; i++) {
    \\        var attr = node.attributes[i];
    \\        if (attr.name !== 'style') {
    \\          attrs[attr.name] = attr.value;
    \\          hasAttrs = true;
    \\        }
    \\      }
    \\      if (hasAttrs) result.attrs = attrs;
    \\    }
    \\    
    \\    // Process children
    \\    var children = [];
    \\    for (var i = 0; i < node.childNodes.length; i++) {
    \\      var child = domToJson(node.childNodes[i]);
    \\      if (child !== null) {
    \\        children.push(child);
    \\      }
    \\    }
    \\    if (children.length > 0) result.children = children;
    \\    
    \\    return result;
    \\  }
    \\  
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  // Table to JSON (array of row objects)
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  function tableToJson(table) {
    \\    var headers = [];
    \\    var headerRow = table.querySelector('thead tr') || table.querySelector('tr');
    \\    if (headerRow) {
    \\      var headerCells = headerRow.querySelectorAll('th, td');
    \\      for (var i = 0; i < headerCells.length; i++) {
    \\        headers.push(headerCells[i].textContent.trim() || ('col' + i));
    \\      }
    \\    }
    \\    
    \\    var rows = table.querySelectorAll('tbody tr');
    \\    if (rows.length === 0) {
    \\      rows = table.querySelectorAll('tr');
    \\      // Skip first row if it was headers
    \\      rows = Array.prototype.slice.call(rows, 1);
    \\    }
    \\    
    \\    var result = [];
    \\    for (var i = 0; i < rows.length; i++) {
    \\      var cells = rows[i].querySelectorAll('td, th');
    \\      var obj = {};
    \\      for (var j = 0; j < cells.length; j++) {
    \\        var key = headers[j] || ('col' + j);
    \\        obj[key] = cells[j].textContent.trim();
    \\      }
    \\      result.push(obj);
    \\    }
    \\    return result;
    \\  }
    \\  
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  // Form to JSON (field name -> value)
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  function formToJson(form) {
    \\    var data = {};
    \\    var elements = form.querySelectorAll('input, select, textarea');
    \\    for (var i = 0; i < elements.length; i++) {
    \\      var el = elements[i];
    \\      var name = el.name || el.id;
    \\      if (!name) continue;
    \\      
    \\      if (el.type === 'checkbox') {
    \\        data[name] = el.checked;
    \\      } else if (el.type === 'radio') {
    \\        if (el.checked) data[name] = el.value;
    \\      } else if (el.multiple) {
    \\        var selected = [];
    \\        for (var j = 0; j < el.selectedOptions.length; j++) {
    \\          selected.push(el.selectedOptions[j].value);
    \\        }
    \\        data[name] = selected;
    \\      } else {
    \\        data[name] = el.value;
    \\      }
    \\    }
    \\    return data;
    \\  }
    \\  
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  // Links extraction (<a href>)
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  function linksToJson(root) {
    \\    var anchors = root.querySelectorAll('a[href]');
    \\    var result = [];
    \\    for (var i = 0; i < anchors.length; i++) {
    \\      var a = anchors[i];
    \\      var entry = { href: a.href };
    \\      var text = a.textContent.trim();
    \\      if (text) entry.text = text;
    \\      if (a.target) entry.target = a.target;
    \\      if (a.rel) entry.rel = a.rel;
    \\      result.push(entry);
    \\    }
    \\    return result;
    \\  }
    \\  
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  // Images extraction (<img>)
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  function imagesToJson(root) {
    \\    var imgs = root.querySelectorAll('img');
    \\    var result = [];
    \\    for (var i = 0; i < imgs.length; i++) {
    \\      var img = imgs[i];
    \\      var entry = { src: img.src };
    \\      if (img.alt) entry.alt = img.alt;
    \\      if (img.naturalWidth) entry.width = img.naturalWidth;
    \\      if (img.naturalHeight) entry.height = img.naturalHeight;
    \\      if (img.srcset) entry.srcset = img.srcset;
    \\      result.push(entry);
    \\    }
    \\    return result;
    \\  }
    \\  
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  // Unified extract function
    \\  // ═══════════════════════════════════════════════════════════════════
    \\  var els = all ? document.querySelectorAll(selector) : [document.querySelector(selector)];
    \\  els = Array.prototype.filter.call(els, function(e) { return e !== null; });
    \\  
    \\  if (els.length === 0) return JSON.stringify(null);
    \\  
    \\  var results = [];
    \\  for (var i = 0; i < els.length; i++) {
    \\    var el = els[i];
    \\    var value;
    \\    switch (mode) {
    \\      case 'text':
    \\        value = el.textContent.trim();
    \\        break;
    \\      case 'html':
    \\        value = el.innerHTML;
    \\        break;
    \\      case 'attrs':
    \\        value = {};
    \\        for (var j = 0; j < el.attributes.length; j++) {
    \\          value[el.attributes[j].name] = el.attributes[j].value;
    \\        }
    \\        break;
    \\      case 'table':
    \\        value = tableToJson(el);
    \\        break;
    \\      case 'form':
    \\        value = formToJson(el);
    \\        break;
    \\      case 'links':
    \\        value = linksToJson(el);
    \\        break;
    \\      case 'images':
    \\        value = imagesToJson(el);
    \\        break;
    \\      case 'dom':
    \\      default:
    \\        value = domToJson(el);
    \\        break;
    \\    }
    \\    results.push(value);
    \\  }
    \\  
    \\  return JSON.stringify(all ? results : results[0], null, 2);
    \\})
;

/// DOM extraction command
pub fn dom(session: *cdp.Session, ctx: CommandCtx) !void {
    if (ctx.positional.len == 0) {
        printDomHelp();
        return;
    }

    const selector = ctx.positional[0];

    // Scan all positional args: collect non-flag args for selector/mode,
    // and detect --all / -a regardless of position.
    var extract_all = false;
    var non_flag_count: usize = 0;
    var mode_str: ?[]const u8 = null;
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--all") or std.mem.eql(u8, arg, "-a")) {
            extract_all = true;
        } else {
            non_flag_count += 1;
            // Second non-flag arg (after selector) is the mode
            if (non_flag_count == 2) mode_str = arg;
        }
    }

    // Parse mode from the second non-flag positional arg
    var mode: ExtractMode = .dom;
    if (mode_str) |ms| {
        if (ExtractMode.fromString(ms)) |m| {
            mode = m;
        } else {
            std.debug.print("Unknown mode: {s}\n", .{ms});
            std.debug.print("Valid modes: dom, text, html, attrs, table, form, links, images\n", .{});
            return;
        }
    }

    // Execute extraction
    const result = try executeExtract(session, ctx.allocator, selector, mode, extract_all);
    defer ctx.allocator.free(result);

    // Output to file or stdout
    if (ctx.output) |output_path| {
        try helpers.writeFile(ctx.io, output_path, result);
        std.debug.print("Extracted to {s}\n", .{output_path});
    } else {
        std.debug.print("{s}\n", .{result});
    }
}

/// Execute DOM extraction and return JSON string
pub fn executeExtract(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    selector: []const u8,
    mode: ExtractMode,
    extract_all: bool,
) ![]const u8 {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Escape selector for JS
    const escaped_selector = try helpers.jsStringLiteral(allocator, selector);
    defer allocator.free(escaped_selector);

    // Build JS expression
    const js = try std.fmt.allocPrint(
        allocator,
        "{s}({s}, '{s}', {s})",
        .{
            extract_js,
            escaped_selector,
            mode.toString(),
            if (extract_all) "true" else "false",
        },
    );
    defer allocator.free(js);

    // Evaluate
    var eval_result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer eval_result.deinit(allocator);

    if (eval_result.value) |v| {
        switch (v) {
            .string => |s| return allocator.dupe(u8, s),
            else => return allocator.dupe(u8, "null"),
        }
    }

    return allocator.dupe(u8, "null");
}

/// Print help for dom command
pub fn printDomHelp() void {
    std.debug.print(
        \\Usage: dom <selector> [mode] [options]
        \\
        \\Extract DOM structure as JSON.
        \\
        \\Modes:
        \\  dom      Full DOM tree structure (default)
        \\  text     Text content only
        \\  html     Raw innerHTML
        \\  attrs    Attributes only
        \\  table    HTML table to array of objects
        \\  form     Form field values as key-value pairs
        \\  links    Extract all links (href, text, target, rel)
        \\  images   Extract all images (src, alt, width, height, srcset)
        \\
        \\Options:
        \\  --all, -a    Extract all matching elements (querySelectorAll)
        \\  --output     Save to file instead of stdout
        \\
        \\Examples:
        \\  dom "#app"                      # Get DOM structure of #app
        \\  dom "table.data" table          # Extract table as JSON array
        \\  dom "form#login" form           # Get form field values
        \\  dom ".item" text --all          # Get text from all .item elements
        \\  dom "#results" --output out.json
        \\  dom "body" links --output links.json
        \\  dom "body" images --output gallery.json
        \\  dom "nav" links                 # Links from nav section only
        \\
    , .{});
}
