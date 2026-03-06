//! DOM extraction command - extract DOM structure as JSON.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const types = @import("types.zig");
const helpers = @import("helpers.zig");
const macro = @import("../cursor/macro/mod.zig");

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
    macro, // Generate macro template JSON

    pub fn fromString(s: []const u8) ?ExtractMode {
        if (std.mem.eql(u8, s, "dom")) return .dom;
        if (std.mem.eql(u8, s, "text")) return .text;
        if (std.mem.eql(u8, s, "html")) return .html;
        if (std.mem.eql(u8, s, "attrs")) return .attrs;
        if (std.mem.eql(u8, s, "table")) return .table;
        if (std.mem.eql(u8, s, "form")) return .form;
        if (std.mem.eql(u8, s, "links")) return .links;
        if (std.mem.eql(u8, s, "images")) return .images;
        if (std.mem.eql(u8, s, "macro")) return .macro;
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
            .macro => "macro",
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

/// JavaScript to inspect element for macro generation
const inspect_element_js =
    \\(function(selector) {
    \\  var el = document.querySelector(selector);
    \\  if (!el) return JSON.stringify(null);
    \\  
    \\  // Build multiple fallback selectors for an element
    \\  function buildSelectors(elem, rootSelector) {
    \\    var sels = [];
    \\    var tag = elem.tagName.toLowerCase();
    \\    
    \\    // Priority 1: ID selector (most stable)
    \\    if (elem.id) sels.push('#' + elem.id);
    \\    
    \\    // Priority 2: name attribute
    \\    if (elem.name) {
    \\      sels.push(rootSelector + ' [name="' + elem.name + '"]');
    \\      sels.push(tag + '[name="' + elem.name + '"]');
    \\    }
    \\    
    \\    // Priority 3: type-based selector for inputs
    \\    if (elem.type && tag === 'input') {
    \\      if (elem.name) {
    \\        sels.push('input[type="' + elem.type + '"][name="' + elem.name + '"]');
    \\      }
    \\      sels.push(rootSelector + ' input[type="' + elem.type + '"]');
    \\    }
    \\    
    \\    // Priority 4: nth-of-type
    \\    var parent = elem.parentElement;
    \\    if (parent) {
    \\      var siblings = parent.querySelectorAll(':scope > ' + tag);
    \\      if (siblings.length > 1) {
    \\        for (var i = 0; i < siblings.length; i++) {
    \\          if (siblings[i] === elem) {
    \\            sels.push(rootSelector + ' ' + tag + ':nth-of-type(' + (i+1) + ')');
    \\            break;
    \\          }
    \\        }
    \\      }
    \\    }
    \\    
    \\    // Fallback: basic tag selector
    \\    sels.push(rootSelector + ' ' + tag);
    \\    
    \\    // Remove duplicates and return
    \\    return sels.filter(function(v, i, a) { return a.indexOf(v) === i; });
    \\  }
    \\  
    \\  var result = {
    \\    tag: el.tagName.toLowerCase(),
    \\    type: el.type || null,
    \\    name: el.name || el.id || null,
    \\    inputs: [],
    \\    submitSelectors: [],
    \\    hasTable: el.tagName === 'TABLE' || !!el.querySelector('table')
    \\  };
    \\  
    \\  // For forms or containers with inputs, discover child inputs
    \\  var inputs = el.querySelectorAll('input, select, textarea');
    \\  for (var i = 0; i < inputs.length; i++) {
    \\    var inp = inputs[i];
    \\    // Skip hidden and submit inputs
    \\    if (inp.type === 'hidden' || inp.type === 'submit') continue;
    \\    result.inputs.push({
    \\      selectors: buildSelectors(inp, selector),
    \\      tag: inp.tagName.toLowerCase(),
    \\      type: inp.type || null,
    \\      name: inp.name || inp.id || null
    \\    });
    \\  }
    \\  
    \\  // Find submit button
    \\  var submit = el.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
    \\  if (submit) {
    \\    result.submitSelectors = buildSelectors(submit, selector);
    \\  }
    \\  
    \\  return JSON.stringify(result);
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
            std.debug.print("Valid modes: dom, text, html, attrs, table, form, links, images, macro\n", .{});
            return;
        }
    }

    // Handle macro mode specially
    if (mode == .macro) {
        if (ctx.output) |output_path| {
            try generateMacroTemplate(session, ctx.allocator, ctx.io, selector, output_path);
        } else {
            std.debug.print("Error: macro mode requires --output <file.json>\n", .{});
            std.debug.print("Example: dom \"#add_record\" macro --output macro.json\n", .{});
        }
        return;
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

/// Element info from JS inspection
const ElementInfo = struct {
    tag: []const u8,
    input_type: ?[]const u8,
    name: ?[]const u8,
    inputs: []InputInfo,
    submit_selectors: [][]const u8,
    has_table: bool,

    pub fn deinit(self: *ElementInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.tag);
        if (self.input_type) |t| allocator.free(t);
        if (self.name) |n| allocator.free(n);
        for (self.submit_selectors) |s| allocator.free(s);
        allocator.free(self.submit_selectors);
        for (self.inputs) |*inp| inp.deinit(allocator);
        allocator.free(self.inputs);
    }
};

const InputInfo = struct {
    selectors: [][]const u8,
    tag: []const u8,
    input_type: ?[]const u8,
    name: ?[]const u8,

    pub fn deinit(self: *InputInfo, allocator: std.mem.Allocator) void {
        for (self.selectors) |s| allocator.free(s);
        allocator.free(self.selectors);
        allocator.free(self.tag);
        if (self.input_type) |t| allocator.free(t);
        if (self.name) |n| allocator.free(n);
    }
};

/// Generate a macro template JSON file for an element
pub fn generateMacroTemplate(
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    selector: []const u8,
    output_path: []const u8,
) !void {
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    // Escape selector for JS
    const escaped_selector = try helpers.jsStringLiteral(allocator, selector);
    defer allocator.free(escaped_selector);

    // Build JS expression for element inspection
    const js = try std.fmt.allocPrint(
        allocator,
        "{s}({s})",
        .{ inspect_element_js, escaped_selector },
    );
    defer allocator.free(js);

    // Evaluate
    var eval_result = try runtime.evaluate(allocator, js, .{ .return_by_value = true });
    defer eval_result.deinit(allocator);

    const json_str = blk: {
        if (eval_result.value) |v| {
            switch (v) {
                .string => |s| break :blk s,
                else => {
                    std.debug.print("Element not found: {s}\n", .{selector});
                    return;
                },
            }
        }
        std.debug.print("Element not found: {s}\n", .{selector});
        return;
    };

    // Parse JSON result
    var parsed = json.parse(allocator, json_str, .{}) catch |err| {
        std.debug.print("Error parsing element info: {}\n", .{err});
        return;
    };
    defer parsed.deinit(allocator);

    if (parsed == .null) {
        std.debug.print("Element not found: {s}\n", .{selector});
        return;
    }

    // Extract element info
    var elem_info = ElementInfo{
        .tag = "",
        .input_type = null,
        .name = null,
        .inputs = &[_]InputInfo{},
        .submit_selectors = &[_][]const u8{},
        .has_table = false,
    };
    defer elem_info.deinit(allocator);

    if (parsed.get("tag")) |t| {
        if (t == .string) elem_info.tag = try allocator.dupe(u8, t.string);
    }
    if (parsed.get("type")) |t| {
        if (t == .string) elem_info.input_type = try allocator.dupe(u8, t.string);
    }
    if (parsed.get("name")) |n| {
        if (n == .string) elem_info.name = try allocator.dupe(u8, n.string);
    }
    if (parsed.get("hasTable")) |h| {
        if (h == .bool) elem_info.has_table = h.bool;
    }

    // Parse submitSelectors array
    if (parsed.get("submitSelectors")) |sels_val| {
        if (sels_val == .array) {
            var sels_list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (sels_list.items) |s| allocator.free(s);
                sels_list.deinit(allocator);
            }
            for (sels_val.array.items) |s_val| {
                if (s_val == .string) {
                    try sels_list.append(allocator, try allocator.dupe(u8, s_val.string));
                }
            }
            elem_info.submit_selectors = try sels_list.toOwnedSlice(allocator);
        }
    }

    // Parse inputs array
    if (parsed.get("inputs")) |inputs_val| {
        if (inputs_val == .array) {
            var inputs_list: std.ArrayList(InputInfo) = .empty;
            errdefer {
                for (inputs_list.items) |*inp| inp.deinit(allocator);
                inputs_list.deinit(allocator);
            }

            for (inputs_val.array.items) |inp_val| {
                if (inp_val != .object) continue;
                var inp = InputInfo{
                    .selectors = &[_][]const u8{},
                    .tag = "",
                    .input_type = null,
                    .name = null,
                };
                // Parse selectors array
                if (inp_val.get("selectors")) |sels_val| {
                    if (sels_val == .array) {
                        var sels_list: std.ArrayList([]const u8) = .empty;
                        errdefer {
                            for (sels_list.items) |s| allocator.free(s);
                            sels_list.deinit(allocator);
                        }
                        for (sels_val.array.items) |s_val| {
                            if (s_val == .string) {
                                try sels_list.append(allocator, try allocator.dupe(u8, s_val.string));
                            }
                        }
                        inp.selectors = try sels_list.toOwnedSlice(allocator);
                    }
                }
                if (inp_val.get("tag")) |t| {
                    if (t == .string) inp.tag = try allocator.dupe(u8, t.string);
                }
                if (inp_val.get("type")) |t| {
                    if (t == .string) inp.input_type = try allocator.dupe(u8, t.string);
                }
                if (inp_val.get("name")) |n| {
                    if (n == .string) inp.name = try allocator.dupe(u8, n.string);
                }
                try inputs_list.append(allocator, inp);
            }
            elem_info.inputs = try inputs_list.toOwnedSlice(allocator);
        }
    }

    // Build macro commands based on element type
    var commands: std.ArrayList(macro.MacroCommand) = .empty;
    defer {
        for (commands.items) |*cmd| cmd.deinit(allocator);
        commands.deinit(allocator);
    }

    // Helper to duplicate selectors array (skip first one which becomes selector)
    const dupeFallbackSelectors = struct {
        fn call(alloc: std.mem.Allocator, sels: [][]const u8) !?[][]const u8 {
            if (sels.len <= 1) return null;
            var fallbacks = try alloc.alloc([]const u8, sels.len - 1);
            for (sels[1..], 0..) |s, i| {
                fallbacks[i] = try alloc.dupe(u8, s);
            }
            return fallbacks;
        }
    }.call;

    // Always start with a wait command
    try commands.append(allocator, .{
        .action = .wait,
        .selector = try allocator.dupe(u8, selector),
    });

    // Generate commands based on element type
    if (elem_info.inputs.len > 0) {
        // Form or container with inputs - generate commands for each input
        for (elem_info.inputs) |inp| {
            const input_type = inp.input_type orelse "text";
            const primary_sel = if (inp.selectors.len > 0) inp.selectors[0] else "";
            if (primary_sel.len == 0) continue;

            if (std.mem.eql(u8, input_type, "checkbox")) {
                try commands.append(allocator, .{
                    .action = .check,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                });
                // Assert after checkbox
                try commands.append(allocator, .{
                    .action = .assert,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                });
            } else if (std.mem.eql(u8, input_type, "radio")) {
                try commands.append(allocator, .{
                    .action = .check,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                });
                // Assert after radio
                try commands.append(allocator, .{
                    .action = .assert,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                });
            } else if (std.mem.eql(u8, input_type, "file")) {
                var files = try allocator.alloc([]const u8, 1);
                files[0] = try allocator.dupe(u8, "TODO.pdf");
                try commands.append(allocator, .{
                    .action = .upload,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                    .files = files,
                });
                // Assert after upload
                try commands.append(allocator, .{
                    .action = .assert,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                });
            } else if (std.mem.eql(u8, inp.tag, "select")) {
                try commands.append(allocator, .{
                    .action = .select,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                    .value = try allocator.dupe(u8, "TODO"),
                });
                // Assert after select
                try commands.append(allocator, .{
                    .action = .assert,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                });
            } else {
                // text, email, password, textarea, etc.
                try commands.append(allocator, .{
                    .action = .fill,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                    .value = try allocator.dupe(u8, "TODO"),
                });
                // Assert after fill
                try commands.append(allocator, .{
                    .action = .assert,
                    .selector = try allocator.dupe(u8, primary_sel),
                    .selectors = try dupeFallbackSelectors(allocator, inp.selectors),
                });
            }
        }

        // Add submit click if found
        if (elem_info.submit_selectors.len > 0) {
            const submit_sel = elem_info.submit_selectors[0];
            try commands.append(allocator, .{
                .action = .click,
                .selector = try allocator.dupe(u8, submit_sel),
                .selectors = try dupeFallbackSelectors(allocator, elem_info.submit_selectors),
            });
        }
    } else if (elem_info.has_table) {
        // Table element - generate extract command
        try commands.append(allocator, .{
            .action = .extract,
            .selector = try allocator.dupe(u8, selector),
            .mode = try allocator.dupe(u8, "table"),
            .output = try allocator.dupe(u8, "table-data.json"),
        });
    } else {
        // Single element - generate action based on tag/type
        const input_type = elem_info.input_type orelse "";

        if (std.mem.eql(u8, input_type, "checkbox")) {
            try commands.append(allocator, .{
                .action = .check,
                .selector = try allocator.dupe(u8, selector),
            });
        } else if (std.mem.eql(u8, input_type, "radio")) {
            try commands.append(allocator, .{
                .action = .check,
                .selector = try allocator.dupe(u8, selector),
            });
        } else if (std.mem.eql(u8, input_type, "file")) {
            var files = try allocator.alloc([]const u8, 1);
            files[0] = try allocator.dupe(u8, "TODO.pdf");
            try commands.append(allocator, .{
                .action = .upload,
                .selector = try allocator.dupe(u8, selector),
                .files = files,
            });
        } else if (std.mem.eql(u8, elem_info.tag, "select")) {
            try commands.append(allocator, .{
                .action = .select,
                .selector = try allocator.dupe(u8, selector),
                .value = try allocator.dupe(u8, "TODO"),
            });
        } else if (std.mem.eql(u8, elem_info.tag, "input") or
            std.mem.eql(u8, elem_info.tag, "textarea"))
        {
            try commands.append(allocator, .{
                .action = .fill,
                .selector = try allocator.dupe(u8, selector),
                .value = try allocator.dupe(u8, "TODO"),
            });
        } else {
            // button, a, div, etc. - default to click
            try commands.append(allocator, .{
                .action = .click,
                .selector = try allocator.dupe(u8, selector),
            });
        }
    }

    // Add final assert command
    try commands.append(allocator, .{
        .action = .assert,
        .selector = try allocator.dupe(u8, selector),
    });

    // Create macro and save
    const command_macro = macro.CommandMacro{
        .version = 2,
        .commands = commands.items,
    };

    try macro.saveCommandMacro(allocator, io, output_path, &command_macro);
    std.debug.print("Generated macro template: {s}\n", .{output_path});
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
        \\  macro    Generate macro template JSON (requires --output)
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
        \\Macro Mode:
        \\  Generate a macro template based on element type.
        \\  The template can be edited and replayed with 'cursor replay'.
        \\
        \\  dom "#add_record" macro --output macro.json
        \\  dom "#login-form" macro --output login.json
        \\  cursor replay macro.json        # Replay the macro
        \\
    , .{});
}
