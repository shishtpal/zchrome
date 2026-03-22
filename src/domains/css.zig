const std = @import("std");
const json = @import("json");
const Session = @import("../core/session.zig").Session;

// ─── Types ──────────────────────────────────────────────────────────────────

/// Stylesheet identifier
pub const StyleSheetId = []const u8;

/// Stylesheet origin
pub const StyleSheetOrigin = enum {
    injected,
    user_agent,
    inspector,
    regular,

    pub fn fromString(s: []const u8) StyleSheetOrigin {
        const map = std.StaticStringMap(StyleSheetOrigin).initComptime(.{
            .{ "injected", .injected },
            .{ "user-agent", .user_agent },
            .{ "inspector", .inspector },
            .{ "regular", .regular },
        });
        return map.get(s) orelse .regular;
    }

    pub fn toString(self: StyleSheetOrigin) []const u8 {
        return switch (self) {
            .injected => "injected",
            .user_agent => "user-agent",
            .inspector => "inspector",
            .regular => "regular",
        };
    }
};

/// CSS stylesheet header information
pub const CSSStyleSheetHeader = struct {
    style_sheet_id: StyleSheetId,
    frame_id: []const u8,
    source_url: []const u8,
    source_map_url: ?[]const u8 = null,
    origin: StyleSheetOrigin,
    title: []const u8,
    owner_node: ?i64 = null,
    disabled: bool = false,
    has_source_url: bool = false,
    is_inline: bool = false,
    is_mutable: bool = false,
    is_constructed: bool = false,
    start_line: f64 = 0,
    start_column: f64 = 0,
    length: f64 = 0,
    end_line: f64 = 0,
    end_column: f64 = 0,

    pub fn deinit(self: *CSSStyleSheetHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.style_sheet_id);
        allocator.free(self.frame_id);
        allocator.free(self.source_url);
        if (self.source_map_url) |url| allocator.free(url);
        allocator.free(self.title);
    }
};

/// Source range in stylesheet
pub const SourceRange = struct {
    start_line: i64,
    start_column: i64,
    end_line: i64,
    end_column: i64,
};

/// CSS property
pub const CSSProperty = struct {
    name: []const u8,
    value: []const u8,
    important: bool = false,
    implicit: bool = false,
    text: ?[]const u8 = null,
    parsed_ok: bool = true,
    disabled: bool = false,
    range: ?SourceRange = null,

    pub fn deinit(self: *CSSProperty, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
        if (self.text) |t| allocator.free(t);
    }
};

/// CSS computed style property (name-value pair)
pub const CSSComputedStyleProperty = struct {
    name: []const u8,
    value: []const u8,

    pub fn deinit(self: *CSSComputedStyleProperty, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

/// CSS style (collection of properties)
pub const CSSStyle = struct {
    style_sheet_id: ?StyleSheetId = null,
    css_properties: []CSSProperty,
    short_hand_entries: []ShorthandEntry = &.{},
    css_text: ?[]const u8 = null,
    range: ?SourceRange = null,

    pub fn deinit(self: *CSSStyle, allocator: std.mem.Allocator) void {
        if (self.style_sheet_id) |id| allocator.free(id);
        for (self.css_properties) |*prop| prop.deinit(allocator);
        allocator.free(self.css_properties);
        for (self.short_hand_entries) |*entry| entry.deinit(allocator);
        if (self.short_hand_entries.len > 0) allocator.free(self.short_hand_entries);
        if (self.css_text) |t| allocator.free(t);
    }
};

/// Shorthand entry
pub const ShorthandEntry = struct {
    name: []const u8,
    value: []const u8,
    important: bool = false,

    pub fn deinit(self: *ShorthandEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

/// CSS rule
pub const CSSRule = struct {
    style_sheet_id: ?StyleSheetId = null,
    selector_list: SelectorList,
    origin: StyleSheetOrigin,
    style: CSSStyle,

    pub fn deinit(self: *CSSRule, allocator: std.mem.Allocator) void {
        if (self.style_sheet_id) |id| allocator.free(id);
        self.selector_list.deinit(allocator);
        self.style.deinit(allocator);
    }
};

/// Selector list
pub const SelectorList = struct {
    selectors: []Selector,
    text: []const u8,

    pub fn deinit(self: *SelectorList, allocator: std.mem.Allocator) void {
        for (self.selectors) |*sel| sel.deinit(allocator);
        allocator.free(self.selectors);
        allocator.free(self.text);
    }
};

/// Single selector
pub const Selector = struct {
    text: []const u8,
    specificity: ?[]i64 = null,

    pub fn deinit(self: *Selector, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.specificity) |s| allocator.free(s);
    }
};

/// Matched CSS rules for a node
pub const RuleMatch = struct {
    rule: CSSRule,
    matching_selectors: []i64,

    pub fn deinit(self: *RuleMatch, allocator: std.mem.Allocator) void {
        self.rule.deinit(allocator);
        allocator.free(self.matching_selectors);
    }
};

// ─── CSS Domain Client ──────────────────────────────────────────────────────

/// CSS domain client for stylesheet inspection and modification
pub const CSS = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable CSS domain events
    pub fn enable(self: *Self) !void {
        var result = try self.session.sendCommand("CSS.enable", .{});
        result.deinit(self.session.allocator);
    }

    /// Disable CSS domain
    pub fn disable(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("CSS.disable", .{});
    }

    /// Get stylesheet text content
    pub fn getStyleSheetText(self: *Self, allocator: std.mem.Allocator, style_sheet_id: StyleSheetId) ![]const u8 {
        var result = try self.session.sendCommand("CSS.getStyleSheetText", .{
            .styleSheetId = style_sheet_id,
        });
        defer result.deinit(self.session.allocator);

        const text = try result.getString("text");
        return allocator.dupe(u8, text);
    }

    /// Set stylesheet text content
    pub fn setStyleSheetText(self: *Self, allocator: std.mem.Allocator, style_sheet_id: StyleSheetId, text: []const u8) ![]const u8 {
        var result = try self.session.sendCommand("CSS.setStyleSheetText", .{
            .styleSheetId = style_sheet_id,
            .text = text,
        });
        defer result.deinit(allocator);

        // Returns source map URL if available
        if (result.get("sourceMapURL")) |v| {
            return allocator.dupe(u8, v.string);
        }
        return allocator.dupe(u8, "");
    }

    /// Get computed styles for a DOM node
    pub fn getComputedStyleForNode(self: *Self, allocator: std.mem.Allocator, node_id: i64) ![]CSSComputedStyleProperty {
        var result = try self.session.sendCommand("CSS.getComputedStyleForNode", .{
            .nodeId = node_id,
        });
        defer result.deinit(self.session.allocator);

        const computed_style = result.get("computedStyle") orelse return error.MissingField;
        const arr = computed_style.asArray() orelse return error.TypeMismatch;

        var props = try allocator.alloc(CSSComputedStyleProperty, arr.len);
        errdefer allocator.free(props);

        for (arr, 0..) |item, i| {
            props[i] = .{
                .name = try allocator.dupe(u8, try item.getString("name")),
                .value = try allocator.dupe(u8, try item.getString("value")),
            };
        }

        return props;
    }

    /// Create a new stylesheet in a frame
    pub fn createStyleSheet(self: *Self, allocator: std.mem.Allocator, frame_id: []const u8) !StyleSheetId {
        var result = try self.session.sendCommand("CSS.createStyleSheet", .{
            .frameId = frame_id,
        });
        defer result.deinit(self.session.allocator);

        const id = try result.getString("styleSheetId");
        return allocator.dupe(u8, id);
    }

    /// Add a CSS rule to a stylesheet
    pub fn addRule(self: *Self, allocator: std.mem.Allocator, style_sheet_id: StyleSheetId, rule_text: []const u8, location: SourceRange) !json.Value {
        _ = allocator;
        const result = try self.session.sendCommand("CSS.addRule", .{
            .styleSheetId = style_sheet_id,
            .ruleText = rule_text,
            .location = .{
                .startLine = location.start_line,
                .startColumn = location.start_column,
                .endLine = location.end_line,
                .endColumn = location.end_column,
            },
        });
        return result;
    }

    /// Get inline styles for a DOM node
    pub fn getInlineStylesForNode(self: *Self, node_id: i64) !json.Value {
        return try self.session.sendCommand("CSS.getInlineStylesForNode", .{
            .nodeId = node_id,
        });
    }

    /// Get matched styles for a DOM node (includes inherited and matched rules)
    pub fn getMatchedStylesForNode(self: *Self, node_id: i64) !json.Value {
        return try self.session.sendCommand("CSS.getMatchedStylesForNode", .{
            .nodeId = node_id,
        });
    }

    /// Force pseudo state for a node (e.g., :hover, :active, :focus)
    pub fn forcePseudoState(self: *Self, node_id: i64, forced_pseudo_classes: []const []const u8) !void {
        try self.session.sendCommandIgnoreResult("CSS.forcePseudoState", .{
            .nodeId = node_id,
            .forcedPseudoClasses = forced_pseudo_classes,
        });
    }

    /// Get the list of all stylesheets
    /// Note: Must have enabled CSS domain first. Stylesheets are reported via events.
    pub fn startRuleUsageTracking(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("CSS.startRuleUsageTracking", .{});
    }

    /// Stop tracking CSS rule usage
    pub fn stopRuleUsageTracking(self: *Self) !json.Value {
        return try self.session.sendCommand("CSS.stopRuleUsageTracking", .{});
    }

    /// Take coverage snapshot
    pub fn takeCoverageDelta(self: *Self) !json.Value {
        return try self.session.sendCommand("CSS.takeCoverageDelta", .{});
    }

    /// Set effective property value for a node
    pub fn setEffectivePropertyValueForNode(self: *Self, node_id: i64, property_name: []const u8, value: []const u8) !void {
        try self.session.sendCommandIgnoreResult("CSS.setEffectivePropertyValueForNode", .{
            .nodeId = node_id,
            .propertyName = property_name,
            .value = value,
        });
    }
};

// ─── Event Types ────────────────────────────────────────────────────────────

/// Fired when a stylesheet is added
pub const StyleSheetAddedEvent = struct {
    header: CSSStyleSheetHeader,

    pub fn deinit(self: *StyleSheetAddedEvent, allocator: std.mem.Allocator) void {
        self.header.deinit(allocator);
    }
};

/// Fired when stylesheet content changes
pub const StyleSheetChangedEvent = struct {
    style_sheet_id: StyleSheetId,

    pub fn deinit(self: *StyleSheetChangedEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.style_sheet_id);
    }
};

/// Fired when a stylesheet is removed
pub const StyleSheetRemovedEvent = struct {
    style_sheet_id: StyleSheetId,

    pub fn deinit(self: *StyleSheetRemovedEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.style_sheet_id);
    }
};

/// Fired when fonts are updated
pub const FontsUpdatedEvent = struct {
    font: ?FontFace = null,

    pub fn deinit(self: *FontsUpdatedEvent, allocator: std.mem.Allocator) void {
        if (self.font) |*f| f.deinit(allocator);
    }
};

/// Font face information
pub const FontFace = struct {
    font_family: []const u8,
    font_style: []const u8,
    font_variant: []const u8,
    font_weight: []const u8,
    font_stretch: []const u8,
    font_display: []const u8,
    unicode_range: []const u8,
    src: []const u8,
    platform_font_family: []const u8,

    pub fn deinit(self: *FontFace, allocator: std.mem.Allocator) void {
        allocator.free(self.font_family);
        allocator.free(self.font_style);
        allocator.free(self.font_variant);
        allocator.free(self.font_weight);
        allocator.free(self.font_stretch);
        allocator.free(self.font_display);
        allocator.free(self.unicode_range);
        allocator.free(self.src);
        allocator.free(self.platform_font_family);
    }
};
