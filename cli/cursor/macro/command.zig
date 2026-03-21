//! Version 2: Semantic Commands (high-level, human-readable)
//!
//! Command-based macros use high-level actions like click, fill, press,
//! with CSS selectors for element targeting.

const std = @import("std");
const json = @import("json");

const escapeString = json.escapeString;

/// Configuration for a single field extraction in "fields" mode
pub const FieldConfig = struct {
    selector: []const u8,
    extract_type: ExtractType = .text,
    attr_name: ?[]const u8 = null, // For type=attr

    pub const ExtractType = enum {
        text, // innerText (default)
        html, // innerHTML
        attr, // Attribute value (requires attr_name)
        value, // Input/select value

        pub fn fromString(s: []const u8) ?ExtractType {
            if (std.mem.eql(u8, s, "text")) return .text;
            if (std.mem.eql(u8, s, "html")) return .html;
            if (std.mem.eql(u8, s, "attr")) return .attr;
            if (std.mem.eql(u8, s, "value")) return .value;
            return null;
        }
    };

    pub fn deinit(self: *FieldConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.selector);
        if (self.attr_name) |a| allocator.free(a);
    }
};

/// Action types for semantic command recording
pub const ActionType = enum {
    click,
    dblclick,
    fill,
    @"type",
    check,
    uncheck,
    select,
    multiselect,
    press,
    scroll,
    hover,
    navigate,
    wait,
    assert,
    extract,
    dialog,
    upload,
    capture,
    goto,
    load, // Load JSON file into variable
    foreach, // Iterate over array variable
    mark, // Explicit status marking (stops execution, signals success/failed/skipped)

    pub fn toString(self: ActionType) []const u8 {
        return switch (self) {
            .click => "click",
            .dblclick => "dblclick",
            .fill => "fill",
            .@"type" => "type",
            .check => "check",
            .uncheck => "uncheck",
            .select => "select",
            .multiselect => "multiselect",
            .press => "press",
            .scroll => "scroll",
            .hover => "hover",
            .navigate => "navigate",
            .wait => "wait",
            .assert => "assert",
            .extract => "extract",
            .dialog => "dialog",
            .upload => "upload",
            .capture => "capture",
            .goto => "goto",
            .load => "load",
            .foreach => "foreach",
            .mark => "mark",
        };
    }

    pub fn fromString(s: []const u8) ?ActionType {
        if (std.mem.eql(u8, s, "click")) return .click;
        if (std.mem.eql(u8, s, "dblclick")) return .dblclick;
        if (std.mem.eql(u8, s, "fill")) return .fill;
        if (std.mem.eql(u8, s, "type")) return .@"type";
        if (std.mem.eql(u8, s, "check")) return .check;
        if (std.mem.eql(u8, s, "uncheck")) return .uncheck;
        if (std.mem.eql(u8, s, "select")) return .select;
        if (std.mem.eql(u8, s, "multiselect")) return .multiselect;
        if (std.mem.eql(u8, s, "press")) return .press;
        if (std.mem.eql(u8, s, "scroll")) return .scroll;
        if (std.mem.eql(u8, s, "hover")) return .hover;
        if (std.mem.eql(u8, s, "navigate")) return .navigate;
        if (std.mem.eql(u8, s, "wait")) return .wait;
        if (std.mem.eql(u8, s, "assert")) return .assert;
        if (std.mem.eql(u8, s, "extract")) return .extract;
        if (std.mem.eql(u8, s, "dialog")) return .dialog;
        if (std.mem.eql(u8, s, "upload")) return .upload;
        if (std.mem.eql(u8, s, "capture")) return .capture;
        if (std.mem.eql(u8, s, "goto")) return .goto;
        if (std.mem.eql(u8, s, "load")) return .load;
        if (std.mem.eql(u8, s, "foreach")) return .foreach;
        if (std.mem.eql(u8, s, "mark")) return .mark;
        return null;
    }

    /// Returns true if this action is a "real" action command (not press/scroll/wait/assert/extract/dialog)
    /// Used to determine where to retry from on assertion failure
    pub fn isActionCommand(self: ActionType) bool {
        return switch (self) {
            .click, .dblclick, .fill, .@"type", .check, .uncheck, .select, .multiselect, .hover, .navigate, .upload => true,
            .press, .scroll, .wait, .assert, .extract, .dialog, .capture, .goto, .load, .foreach, .mark => false,
        };
    }
};

/// A semantic command (click, fill, press, assert, dialog, etc.)
pub const MacroCommand = struct {
    action: ActionType,
    selector: ?[]const u8 = null, // CSS selector for element (primary)
    selectors: ?[][]const u8 = null, // Fallback selectors for dynamic pages
    value: ?[]const u8 = null, // Text value for fill/select, URL for navigate, prompt text for dialog
    key: ?[]const u8 = null, // Key name for press
    scroll_x: ?i32 = null, // Scroll delta X
    scroll_y: ?i32 = null, // Scroll delta Y
    // Assert-specific fields
    attribute: ?[]const u8 = null, // Attribute name to check (for assert)
    contains: ?[]const u8 = null, // Substring to find in attribute/text (for assert)
    url: ?[]const u8 = null, // URL pattern to match (for assert)
    text: ?[]const u8 = null, // Text to find on page (for assert), or expected dialog message (for dialog)
    timeout: ?u32 = null, // Timeout in ms (default: 5000)
    fallback: ?[]const u8 = null, // Fallback JSON file on assertion failure
    // Count assertion fields
    count: ?u32 = null, // Exact element count
    count_min: ?u32 = null, // Minimum element count
    count_max: ?u32 = null, // Maximum element count
    // Extract-specific fields
    mode: ?[]const u8 = null, // Extraction mode: dom, text, html, attrs, table, form
    output: ?[]const u8 = null, // Output file path for extract
    extract_all: ?bool = null, // Use querySelectorAll for extract
    append: ?bool = null, // Append to existing JSON array instead of overwrite
    dedupe_key: ?[]const u8 = null, // Path to unique key for deduplication (e.g., "attrs.data-user-id")
    fields: ?std.StringArrayHashMapUnmanaged(FieldConfig) = null, // Multi-selector field extraction
    // Snapshot assertion field
    snapshot: ?[]const u8 = null, // Expected JSON file for snapshot comparison
    // Dialog-specific fields
    accept: ?bool = null, // For dialog: true=accept (OK), false=dismiss (Cancel)
    // Upload-specific fields
    files: ?[][]const u8 = null, // File paths for upload action
    // Capture-specific fields
    count_as: ?[]const u8 = null, // Variable name to store element count
    text_as: ?[]const u8 = null, // Variable name to store text content
    value_as: ?[]const u8 = null, // Variable name to store input value
    attr_as: ?[]const u8 = null, // Variable name to store attribute value
    // Comparison assertion fields (for use with captured variables)
    count_gt: ?[]const u8 = null, // Count greater than (value or $variable)
    count_lt: ?[]const u8 = null, // Count less than (value or $variable)
    count_gte: ?[]const u8 = null, // Count greater than or equal
    count_lte: ?[]const u8 = null, // Count less than or equal
    text_eq: ?[]const u8 = null, // Text equals (value or $variable)
    text_neq: ?[]const u8 = null, // Text not equals
    text_contains_var: ?[]const u8 = null, // Text contains (value or $variable)
    value_eq: ?[]const u8 = null, // Input value equals
    value_neq: ?[]const u8 = null, // Input value not equals
    // Goto-specific fields
    file: ?[]const u8 = null, // Target macro JSON file for goto action
    // Load-specific fields
    as_var: ?[]const u8 = null, // Variable name to store loaded data (for load action)
    // Foreach-specific fields
    source: ?[]const u8 = null, // Variable name containing array to iterate (e.g., "$users")
    on_error: ?[]const u8 = null, // Error handling: "continue" (default) or "stop"
    progress_file: ?[]const u8 = null, // File to track progress for resume

    pub fn deinit(self: *MacroCommand, allocator: std.mem.Allocator) void {
        if (self.selector) |s| allocator.free(s);
        if (self.selectors) |sels| {
            for (sels) |sel| allocator.free(sel);
            allocator.free(sels);
        }
        if (self.value) |v| allocator.free(v);
        if (self.key) |k| allocator.free(k);
        if (self.attribute) |a| allocator.free(a);
        if (self.contains) |c| allocator.free(c);
        if (self.url) |u| allocator.free(u);
        if (self.text) |t| allocator.free(t);
        if (self.fallback) |f| allocator.free(f);
        if (self.mode) |m| allocator.free(m);
        if (self.output) |o| allocator.free(o);
        if (self.dedupe_key) |dk| allocator.free(dk);
        if (self.snapshot) |sn| allocator.free(sn);
        // Fields extraction
        if (self.fields) |*flds| {
            for (flds.keys(), flds.values()) |key, *val| {
                allocator.free(key);
                val.deinit(allocator);
            }
            flds.deinit(allocator);
        }
        if (self.files) |f| {
            for (f) |file| allocator.free(file);
            allocator.free(f);
        }
        // Capture fields
        if (self.count_as) |ca| allocator.free(ca);
        if (self.text_as) |ta| allocator.free(ta);
        if (self.value_as) |va| allocator.free(va);
        if (self.attr_as) |aa| allocator.free(aa);
        // Comparison fields
        if (self.count_gt) |cg| allocator.free(cg);
        if (self.count_lt) |cl| allocator.free(cl);
        if (self.count_gte) |cge| allocator.free(cge);
        if (self.count_lte) |cle| allocator.free(cle);
        if (self.text_eq) |te| allocator.free(te);
        if (self.text_neq) |tn| allocator.free(tn);
        if (self.text_contains_var) |tc| allocator.free(tc);
        if (self.value_eq) |ve| allocator.free(ve);
        if (self.value_neq) |vn| allocator.free(vn);
        // Goto fields
        if (self.file) |f2| allocator.free(f2);
        // Load fields
        if (self.as_var) |av| allocator.free(av);
        // Foreach fields
        if (self.source) |src| allocator.free(src);
        if (self.on_error) |oe| allocator.free(oe);
        if (self.progress_file) |pf| allocator.free(pf);
    }

    pub fn clone(self: *const MacroCommand, allocator: std.mem.Allocator) !MacroCommand {
        var cloned_selectors: ?[][]const u8 = null;
        if (self.selectors) |sels| {
            var new_sels = try allocator.alloc([]const u8, sels.len);
            for (sels, 0..) |sel, i| {
                new_sels[i] = try allocator.dupe(u8, sel);
            }
            cloned_selectors = new_sels;
        }
        var cloned_files: ?[][]const u8 = null;
        if (self.files) |f| {
            var new_files = try allocator.alloc([]const u8, f.len);
            for (f, 0..) |file, i| {
                new_files[i] = try allocator.dupe(u8, file);
            }
            cloned_files = new_files;
        }
        return .{
            .action = self.action,
            .selector = if (self.selector) |s| try allocator.dupe(u8, s) else null,
            .selectors = cloned_selectors,
            .value = if (self.value) |v| try allocator.dupe(u8, v) else null,
            .key = if (self.key) |k| try allocator.dupe(u8, k) else null,
            .scroll_x = self.scroll_x,
            .scroll_y = self.scroll_y,
            .attribute = if (self.attribute) |a| try allocator.dupe(u8, a) else null,
            .contains = if (self.contains) |c| try allocator.dupe(u8, c) else null,
            .url = if (self.url) |u| try allocator.dupe(u8, u) else null,
            .text = if (self.text) |t| try allocator.dupe(u8, t) else null,
            .timeout = self.timeout,
            .fallback = if (self.fallback) |f| try allocator.dupe(u8, f) else null,
            .count = self.count,
            .count_min = self.count_min,
            .count_max = self.count_max,
            .mode = if (self.mode) |m| try allocator.dupe(u8, m) else null,
            .output = if (self.output) |o| try allocator.dupe(u8, o) else null,
            .extract_all = self.extract_all,
            .append = self.append,
            .dedupe_key = if (self.dedupe_key) |dk| try allocator.dupe(u8, dk) else null,
            .snapshot = if (self.snapshot) |sn| try allocator.dupe(u8, sn) else null,
            .accept = self.accept,
            .files = cloned_files,
            // Capture fields
            .count_as = if (self.count_as) |ca| try allocator.dupe(u8, ca) else null,
            .text_as = if (self.text_as) |ta| try allocator.dupe(u8, ta) else null,
            .value_as = if (self.value_as) |va| try allocator.dupe(u8, va) else null,
            .attr_as = if (self.attr_as) |aa| try allocator.dupe(u8, aa) else null,
            // Comparison fields
            .count_gt = if (self.count_gt) |cg| try allocator.dupe(u8, cg) else null,
            .count_lt = if (self.count_lt) |cl| try allocator.dupe(u8, cl) else null,
            .count_gte = if (self.count_gte) |cge| try allocator.dupe(u8, cge) else null,
            .count_lte = if (self.count_lte) |cle| try allocator.dupe(u8, cle) else null,
            .text_eq = if (self.text_eq) |te| try allocator.dupe(u8, te) else null,
            .text_neq = if (self.text_neq) |tn| try allocator.dupe(u8, tn) else null,
            .text_contains_var = if (self.text_contains_var) |tc| try allocator.dupe(u8, tc) else null,
            .value_eq = if (self.value_eq) |ve| try allocator.dupe(u8, ve) else null,
            .value_neq = if (self.value_neq) |vn| try allocator.dupe(u8, vn) else null,
            .file = if (self.file) |f2| try allocator.dupe(u8, f2) else null,
            // Load fields
            .as_var = if (self.as_var) |av| try allocator.dupe(u8, av) else null,
            // Foreach fields
            .source = if (self.source) |src| try allocator.dupe(u8, src) else null,
            .on_error = if (self.on_error) |oe| try allocator.dupe(u8, oe) else null,
            .progress_file = if (self.progress_file) |pf| try allocator.dupe(u8, pf) else null,
        };
    }
};

/// Command-based macro (version 2)
pub const CommandMacro = struct {
    version: u32 = 2,
    commands: []MacroCommand,

    pub fn deinit(self: *CommandMacro, allocator: std.mem.Allocator) void {
        for (self.commands) |*c| {
            c.deinit(allocator);
        }
        allocator.free(self.commands);
    }
};

/// Save a command macro to JSON file
pub fn save(allocator: std.mem.Allocator, io: std.Io, path: []const u8, macro: *const CommandMacro) !void {
    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try json_buf.appendSlice(allocator, "{\n");
    try json_buf.appendSlice(allocator, "  \"version\": 2,\n");
    try json_buf.appendSlice(allocator, "  \"commands\": [\n");

    for (macro.commands, 0..) |cmd, i| {
        if (i > 0) try json_buf.appendSlice(allocator, ",\n");
        try json_buf.appendSlice(allocator, "    {");

        // Action
        try json_buf.appendSlice(allocator, "\"action\": \"");
        try json_buf.appendSlice(allocator, cmd.action.toString());
        try json_buf.appendSlice(allocator, "\"");

        // Selector (primary)
        if (cmd.selector) |sel| {
            const escaped = try escapeString(allocator, sel);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"selector\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Selectors (fallback list)
        if (cmd.selectors) |sels| {
            try json_buf.appendSlice(allocator, ", \"selectors\": [");
            for (sels, 0..) |sel, j| {
                if (j > 0) try json_buf.appendSlice(allocator, ", ");
                const escaped = try escapeString(allocator, sel);
                defer allocator.free(escaped);
                try json_buf.appendSlice(allocator, "\"");
                try json_buf.appendSlice(allocator, escaped);
                try json_buf.appendSlice(allocator, "\"");
            }
            try json_buf.appendSlice(allocator, "]");
        }

        // Value
        if (cmd.value) |val| {
            const escaped = try escapeString(allocator, val);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"value\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Key
        if (cmd.key) |key| {
            const escaped = try escapeString(allocator, key);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"key\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        // Scroll
        if (cmd.scroll_x) |sx| {
            const sx_str = try std.fmt.allocPrint(allocator, ", \"scrollX\": {}", .{sx});
            defer allocator.free(sx_str);
            try json_buf.appendSlice(allocator, sx_str);
        }
        if (cmd.scroll_y) |sy| {
            const sy_str = try std.fmt.allocPrint(allocator, ", \"scrollY\": {}", .{sy});
            defer allocator.free(sy_str);
            try json_buf.appendSlice(allocator, sy_str);
        }

        // Assert-specific fields
        if (cmd.attribute) |attr| {
            const escaped = try escapeString(allocator, attr);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"attribute\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.contains) |cont| {
            const escaped = try escapeString(allocator, cont);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"contains\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.url) |url_val| {
            const escaped = try escapeString(allocator, url_val);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"url\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.text) |txt| {
            const escaped = try escapeString(allocator, txt);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"text\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.timeout) |to| {
            const to_str = try std.fmt.allocPrint(allocator, ", \"timeout\": {}", .{to});
            defer allocator.free(to_str);
            try json_buf.appendSlice(allocator, to_str);
        }
        if (cmd.fallback) |fb| {
            const escaped = try escapeString(allocator, fb);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"fallback\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        // Count assertion fields
        if (cmd.count) |c| {
            const c_str = try std.fmt.allocPrint(allocator, ", \"count\": {}", .{c});
            defer allocator.free(c_str);
            try json_buf.appendSlice(allocator, c_str);
        }
        if (cmd.count_min) |c| {
            const c_str = try std.fmt.allocPrint(allocator, ", \"count_min\": {}", .{c});
            defer allocator.free(c_str);
            try json_buf.appendSlice(allocator, c_str);
        }
        if (cmd.count_max) |c| {
            const c_str = try std.fmt.allocPrint(allocator, ", \"count_max\": {}", .{c});
            defer allocator.free(c_str);
            try json_buf.appendSlice(allocator, c_str);
        }

        // Extract-specific fields
        if (cmd.mode) |m| {
            const escaped = try escapeString(allocator, m);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"mode\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.output) |o| {
            const escaped = try escapeString(allocator, o);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"output\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.extract_all) |ea| {
            try json_buf.appendSlice(allocator, if (ea) ", \"extract_all\": true" else ", \"extract_all\": false");
        }
        if (cmd.append) |ap| {
            try json_buf.appendSlice(allocator, if (ap) ", \"append\": true" else ", \"append\": false");
        }
        if (cmd.dedupe_key) |dk| {
            const escaped = try escapeString(allocator, dk);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"key\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        // Snapshot assertion field
        if (cmd.snapshot) |sn| {
            const escaped = try escapeString(allocator, sn);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"snapshot\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        // Dialog-specific field
        if (cmd.accept) |ac| {
            try json_buf.appendSlice(allocator, if (ac) ", \"accept\": true" else ", \"accept\": false");
        }
        // Upload-specific field
        if (cmd.files) |f| {
            try json_buf.appendSlice(allocator, ", \"files\": [");
            for (f, 0..) |file, j| {
                if (j > 0) try json_buf.appendSlice(allocator, ", ");
                const escaped = try escapeString(allocator, file);
                defer allocator.free(escaped);
                try json_buf.appendSlice(allocator, "\"");
                try json_buf.appendSlice(allocator, escaped);
                try json_buf.appendSlice(allocator, "\"");
            }
            try json_buf.appendSlice(allocator, "]");
        }
        // Capture-specific fields
        if (cmd.count_as) |ca| {
            const escaped = try escapeString(allocator, ca);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"count_as\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.text_as) |ta| {
            const escaped = try escapeString(allocator, ta);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"text_as\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.value_as) |va| {
            const escaped = try escapeString(allocator, va);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"value_as\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.attr_as) |aa| {
            const escaped = try escapeString(allocator, aa);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"attr_as\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        // Comparison assertion fields
        if (cmd.count_gt) |cg| {
            const escaped = try escapeString(allocator, cg);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"count_gt\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.count_lt) |cl| {
            const escaped = try escapeString(allocator, cl);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"count_lt\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.count_gte) |cge| {
            const escaped = try escapeString(allocator, cge);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"count_gte\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.count_lte) |cle| {
            const escaped = try escapeString(allocator, cle);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"count_lte\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.text_eq) |te| {
            const escaped = try escapeString(allocator, te);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"text_eq\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.text_neq) |tn| {
            const escaped = try escapeString(allocator, tn);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"text_neq\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.text_contains_var) |tc| {
            const escaped = try escapeString(allocator, tc);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"text_contains\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.value_eq) |ve| {
            const escaped = try escapeString(allocator, ve);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"value_eq\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.value_neq) |vn| {
            const escaped = try escapeString(allocator, vn);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"value_neq\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.file) |f| {
            const escaped = try escapeString(allocator, f);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"file\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        // Load-specific field
        if (cmd.as_var) |av| {
            const escaped = try escapeString(allocator, av);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"as\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        // Foreach-specific fields
        if (cmd.source) |src| {
            const escaped = try escapeString(allocator, src);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"source\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.on_error) |oe| {
            const escaped = try escapeString(allocator, oe);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"on_error\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }
        if (cmd.progress_file) |pf| {
            const escaped = try escapeString(allocator, pf);
            defer allocator.free(escaped);
            try json_buf.appendSlice(allocator, ", \"progress_file\": \"");
            try json_buf.appendSlice(allocator, escaped);
            try json_buf.appendSlice(allocator, "\"");
        }

        try json_buf.appendSlice(allocator, "}");
    }

    try json_buf.appendSlice(allocator, "\n  ]\n}\n");

    // Write to file
    const dir = std.Io.Dir.cwd();
    dir.writeFile(io, .{
        .sub_path = path,
        .data = json_buf.items,
    }) catch |err| {
        std.debug.print("Error writing macro file: {}\n", .{err});
        return err;
    };
}

/// Load a command macro from JSON file
pub fn load(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !CommandMacro {
    const dir = std.Io.Dir.cwd();
    var file_buf: [256 * 1024]u8 = undefined;
    const content = dir.readFile(io, path, &file_buf) catch |err| {
        std.debug.print("Error reading macro file: {}\n", .{err});
        return err;
    };

    var parsed = json.parse(allocator, content, .{}) catch |err| {
        std.debug.print("Error parsing macro JSON: {}\n", .{err});
        return err;
    };
    defer parsed.deinit(allocator);

    var macro = CommandMacro{
        .version = 2,
        .commands = &[_]MacroCommand{},
    };

    if (parsed.get("commands")) |cmds_val| {
        if (cmds_val == .array) {
            var cmds_list: std.ArrayList(MacroCommand) = .empty;
            errdefer {
                for (cmds_list.items) |*c| c.deinit(allocator);
                cmds_list.deinit(allocator);
            }

            for (cmds_val.array.items) |cmd_val| {
                if (cmd_val != .object) continue;
                const obj = cmd_val.object;

                var cmd = MacroCommand{ .action = .click };

                if (obj.get("action")) |a| {
                    if (a == .string) {
                        if (ActionType.fromString(a.string)) |action| {
                            cmd.action = action;
                        }
                    }
                }

                if (obj.get("selector")) |s| {
                    if (s == .string) cmd.selector = try allocator.dupe(u8, s.string);
                }
                if (obj.get("selectors")) |sels_val| {
                    if (sels_val == .array) {
                        var sels_list: std.ArrayList([]const u8) = .empty;
                        errdefer {
                            for (sels_list.items) |sel| allocator.free(sel);
                            sels_list.deinit(allocator);
                        }
                        for (sels_val.array.items) |sel_val| {
                            if (sel_val == .string) {
                                try sels_list.append(allocator, try allocator.dupe(u8, sel_val.string));
                            }
                        }
                        if (sels_list.items.len > 0) {
                            cmd.selectors = try sels_list.toOwnedSlice(allocator);
                        } else {
                            sels_list.deinit(allocator);
                        }
                    }
                }
                if (obj.get("value")) |v| {
                    if (v == .string) {
                        cmd.value = try allocator.dupe(u8, v.string);
                    } else if (v == .integer) {
                        cmd.value = try std.fmt.allocPrint(allocator, "{}", .{v.integer});
                    }
                }
                if (obj.get("key")) |k| {
                    if (k == .string) cmd.key = try allocator.dupe(u8, k.string);
                }
                if (obj.get("scrollX")) |sx| {
                    if (sx == .integer) cmd.scroll_x = @intCast(sx.integer);
                }
                if (obj.get("scrollY")) |sy| {
                    if (sy == .integer) cmd.scroll_y = @intCast(sy.integer);
                }
                // Assert-specific fields
                if (obj.get("attribute")) |attr| {
                    if (attr == .string) cmd.attribute = try allocator.dupe(u8, attr.string);
                }
                if (obj.get("contains")) |cont| {
                    if (cont == .string) cmd.contains = try allocator.dupe(u8, cont.string);
                }
                if (obj.get("url")) |url_val| {
                    if (url_val == .string) cmd.url = try allocator.dupe(u8, url_val.string);
                }
                if (obj.get("text")) |txt| {
                    if (txt == .string) cmd.text = try allocator.dupe(u8, txt.string);
                }
                if (obj.get("timeout")) |to| {
                    if (to == .integer) cmd.timeout = @intCast(to.integer);
                }
                if (obj.get("fallback")) |fb| {
                    if (fb == .string) cmd.fallback = try allocator.dupe(u8, fb.string);
                }
                // Count assertion fields
                if (obj.get("count")) |c| {
                    if (c == .integer) cmd.count = @intCast(c.integer);
                }
                if (obj.get("count_min")) |c| {
                    if (c == .integer) cmd.count_min = @intCast(c.integer);
                }
                if (obj.get("count_max")) |c| {
                    if (c == .integer) cmd.count_max = @intCast(c.integer);
                }
                // Extract-specific fields
                if (obj.get("mode")) |m| {
                    if (m == .string) cmd.mode = try allocator.dupe(u8, m.string);
                }
                if (obj.get("output")) |o| {
                    if (o == .string) cmd.output = try allocator.dupe(u8, o.string);
                }
                if (obj.get("extract_all")) |ea| {
                    if (ea == .bool) cmd.extract_all = ea.bool;
                }
                if (obj.get("append")) |ap| {
                    if (ap == .bool) cmd.append = ap.bool;
                }
                if (obj.get("key")) |dk| {
                    if (dk == .string) cmd.dedupe_key = try allocator.dupe(u8, dk.string);
                }
                // Fields extraction (multi-selector)
                if (obj.get("fields")) |fields_val| {
                    if (fields_val == .object) {
                        var fields_map: std.StringArrayHashMapUnmanaged(FieldConfig) = .{};
                        errdefer {
                            for (fields_map.keys(), fields_map.values()) |key, *val| {
                                allocator.free(key);
                                val.deinit(allocator);
                            }
                            fields_map.deinit(allocator);
                        }

                        var fields_iter = fields_val.object.iterator();
                        while (fields_iter.next()) |entry| {
                            const field_name = try allocator.dupe(u8, entry.key_ptr.*);
                            errdefer allocator.free(field_name);

                            var config: FieldConfig = undefined;

                            // Simple syntax: "field": "selector" (string)
                            if (entry.value_ptr.* == .string) {
                                config = .{
                                    .selector = try allocator.dupe(u8, entry.value_ptr.string),
                                    .extract_type = .text,
                                    .attr_name = null,
                                };
                            }
                            // Advanced syntax: "field": {"selector": "...", "type": "...", "attr": "..."}
                            else if (entry.value_ptr.* == .object) {
                                const field_obj = entry.value_ptr.object;
                                const sel = field_obj.get("selector") orelse {
                                    std.debug.print("Warning: field '{s}' missing 'selector', skipping\n", .{field_name});
                                    allocator.free(field_name);
                                    continue;
                                };
                                if (sel != .string) {
                                    std.debug.print("Warning: field '{s}' selector is not a string, skipping\n", .{field_name});
                                    allocator.free(field_name);
                                    continue;
                                }

                                var extract_type: FieldConfig.ExtractType = .text;
                                if (field_obj.get("type")) |t| {
                                    if (t == .string) {
                                        extract_type = FieldConfig.ExtractType.fromString(t.string) orelse .text;
                                    }
                                }

                                var attr_name: ?[]const u8 = null;
                                if (field_obj.get("attr")) |a| {
                                    if (a == .string) {
                                        attr_name = try allocator.dupe(u8, a.string);
                                    }
                                }

                                config = .{
                                    .selector = try allocator.dupe(u8, sel.string),
                                    .extract_type = extract_type,
                                    .attr_name = attr_name,
                                };
                            } else {
                                std.debug.print("Warning: field '{s}' value must be string or object, skipping\n", .{field_name});
                                allocator.free(field_name);
                                continue;
                            }

                            try fields_map.put(allocator, field_name, config);
                        }

                        if (fields_map.count() > 0) {
                            cmd.fields = fields_map;
                        } else {
                            fields_map.deinit(allocator);
                        }
                    }
                }
                // Snapshot assertion field
                if (obj.get("snapshot")) |sn| {
                    if (sn == .string) cmd.snapshot = try allocator.dupe(u8, sn.string);
                }
                // Dialog-specific field
                if (obj.get("accept")) |ac| {
                    if (ac == .bool) cmd.accept = ac.bool;
                }
                // Upload-specific field
                if (obj.get("files")) |files_val| {
                    if (files_val == .array) {
                        var files_list: std.ArrayList([]const u8) = .empty;
                        errdefer {
                            for (files_list.items) |f| allocator.free(f);
                            files_list.deinit(allocator);
                        }
                        for (files_val.array.items) |f_val| {
                            if (f_val == .string) {
                                try files_list.append(allocator, try allocator.dupe(u8, f_val.string));
                            }
                        }
                        if (files_list.items.len > 0) {
                            cmd.files = try files_list.toOwnedSlice(allocator);
                        } else {
                            files_list.deinit(allocator);
                        }
                    }
                }
                // Capture-specific fields
                if (obj.get("count_as")) |ca| {
                    if (ca == .string) cmd.count_as = try allocator.dupe(u8, ca.string);
                }
                if (obj.get("text_as")) |ta| {
                    if (ta == .string) cmd.text_as = try allocator.dupe(u8, ta.string);
                }
                if (obj.get("value_as")) |va| {
                    if (va == .string) cmd.value_as = try allocator.dupe(u8, va.string);
                }
                if (obj.get("attr_as")) |aa| {
                    if (aa == .string) cmd.attr_as = try allocator.dupe(u8, aa.string);
                }
                // Comparison assertion fields
                if (obj.get("count_gt")) |cg| {
                    if (cg == .string) cmd.count_gt = try allocator.dupe(u8, cg.string);
                }
                if (obj.get("count_lt")) |cl| {
                    if (cl == .string) cmd.count_lt = try allocator.dupe(u8, cl.string);
                }
                if (obj.get("count_gte")) |cge| {
                    if (cge == .string) cmd.count_gte = try allocator.dupe(u8, cge.string);
                }
                if (obj.get("count_lte")) |cle| {
                    if (cle == .string) cmd.count_lte = try allocator.dupe(u8, cle.string);
                }
                if (obj.get("text_eq")) |te| {
                    if (te == .string) cmd.text_eq = try allocator.dupe(u8, te.string);
                }
                if (obj.get("text_neq")) |tn| {
                    if (tn == .string) cmd.text_neq = try allocator.dupe(u8, tn.string);
                }
                if (obj.get("text_contains")) |tc| {
                    if (tc == .string) cmd.text_contains_var = try allocator.dupe(u8, tc.string);
                }
                if (obj.get("value_eq")) |ve| {
                    if (ve == .string) cmd.value_eq = try allocator.dupe(u8, ve.string);
                }
                if (obj.get("value_neq")) |vn| {
                    if (vn == .string) cmd.value_neq = try allocator.dupe(u8, vn.string);
                }
                // Goto-specific field
                if (obj.get("file")) |f| {
                    if (f == .string) cmd.file = try allocator.dupe(u8, f.string);
                }
                // Load-specific field
                if (obj.get("as")) |av| {
                    if (av == .string) cmd.as_var = try allocator.dupe(u8, av.string);
                }
                // Foreach-specific fields
                if (obj.get("source")) |src| {
                    if (src == .string) cmd.source = try allocator.dupe(u8, src.string);
                }
                if (obj.get("on_error")) |oe| {
                    if (oe == .string) cmd.on_error = try allocator.dupe(u8, oe.string);
                }
                if (obj.get("progress_file")) |pf| {
                    if (pf == .string) cmd.progress_file = try allocator.dupe(u8, pf.string);
                }

                try cmds_list.append(allocator, cmd);
            }

            macro.commands = try cmds_list.toOwnedSlice(allocator);
        }
    }

    return macro;
}
