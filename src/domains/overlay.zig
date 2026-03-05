const std = @import("std");
const Session = @import("../core/session.zig").Session;

/// Overlay domain client for DOM element highlighting
pub const Overlay = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable overlay domain
    pub fn enable(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Overlay.enable", .{});
    }

    /// Disable overlay domain
    pub fn disable(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Overlay.disable", .{});
    }

    /// Hide any visible highlight
    pub fn hideHighlight(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Overlay.hideHighlight", .{});
    }

    /// Highlight a DOM node
    pub fn highlightNode(self: *Self, config: HighlightConfig, node_id: ?i64, backend_node_id: ?i64, object_id: ?[]const u8, selector: ?[]const u8) !void {
        try self.session.sendCommandIgnoreResult("Overlay.highlightNode", .{
            .highlightConfig = .{
                .showInfo = config.show_info,
                .showStyles = config.show_styles,
                .showRulers = config.show_rulers,
                .showAccessibilityInfo = config.show_accessibility_info,
                .showExtensionLines = config.show_extension_lines,
                .contentColor = if (config.content_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                .paddingColor = if (config.padding_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                .borderColor = if (config.border_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                .marginColor = if (config.margin_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
            },
            .nodeId = node_id,
            .backendNodeId = backend_node_id,
            .objectId = object_id,
            .selector = selector,
        });
    }

    /// Highlight a quad (arbitrary quadrilateral)
    pub fn highlightQuad(self: *Self, quad: [8]f64, color: ?RGBA, outline_color: ?RGBA) !void {
        try self.session.sendCommandIgnoreResult("Overlay.highlightQuad", .{
            .quad = quad,
            .color = if (color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
            .outlineColor = if (outline_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
        });
    }

    /// Highlight a rectangular area
    pub fn highlightRect(self: *Self, x: i32, y: i32, width: i32, height: i32, color: ?RGBA, outline_color: ?RGBA) !void {
        try self.session.sendCommandIgnoreResult("Overlay.highlightRect", .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .color = if (color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
            .outlineColor = if (outline_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
        });
    }

    /// Highlight a source order (for accessibility)
    pub fn highlightSourceOrder(self: *Self, config: SourceOrderConfig, node_id: ?i64, backend_node_id: ?i64, object_id: ?[]const u8) !void {
        try self.session.sendCommandIgnoreResult("Overlay.highlightSourceOrder", .{
            .sourceOrderConfig = .{
                .parentOutlineColor = if (config.parent_outline_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                .childOutlineColor = if (config.child_outline_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
            },
            .nodeId = node_id,
            .backendNodeId = backend_node_id,
            .objectId = object_id,
        });
    }

    /// Set inspect mode
    pub fn setInspectMode(self: *Self, mode: []const u8, config: ?HighlightConfig) !void {
        if (config) |cfg| {
            try self.session.sendCommandIgnoreResult("Overlay.setInspectMode", .{
                .mode = mode,
                .highlightConfig = .{
                    .showInfo = cfg.show_info,
                    .showStyles = cfg.show_styles,
                    .showRulers = cfg.show_rulers,
                    .contentColor = if (cfg.content_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                    .paddingColor = if (cfg.padding_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                    .borderColor = if (cfg.border_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                    .marginColor = if (cfg.margin_color) |c| .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } else null,
                },
            });
        } else {
            try self.session.sendCommandIgnoreResult("Overlay.setInspectMode", .{
                .mode = mode,
            });
        }
    }

    /// Set paused in debugger message
    pub fn setPausedInDebuggerMessage(self: *Self, message: ?[]const u8) !void {
        try self.session.sendCommandIgnoreResult("Overlay.setPausedInDebuggerMessage", .{
            .message = message,
        });
    }

    /// Show debug border for elements
    pub fn setShowDebugBorders(self: *Self, show: bool) !void {
        try self.session.sendCommandIgnoreResult("Overlay.setShowDebugBorders", .{
            .show = show,
        });
    }

    /// Show FPS counter
    pub fn setShowFPSCounter(self: *Self, show: bool) !void {
        try self.session.sendCommandIgnoreResult("Overlay.setShowFPSCounter", .{
            .show = show,
        });
    }

    /// Show paint rectangles
    pub fn setShowPaintRects(self: *Self, result: bool) !void {
        try self.session.sendCommandIgnoreResult("Overlay.setShowPaintRects", .{
            .result = result,
        });
    }

    /// Show scroll snap overlays
    pub fn setShowScrollSnapOverlays(self: *Self, scroll_snap_highlight_configs: []const ScrollSnapHighlightConfig) !void {
        try self.session.sendCommandIgnoreResult("Overlay.setShowScrollSnapOverlays", .{
            .scrollSnapHighlightConfigs = scroll_snap_highlight_configs,
        });
    }

    /// Show viewport size on resize
    pub fn setShowViewportSizeOnResize(self: *Self, show: bool) !void {
        try self.session.sendCommandIgnoreResult("Overlay.setShowViewportSizeOnResize", .{
            .show = show,
        });
    }
};

/// RGBA color
pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: ?f64 = null,

    /// Create a color from hex value
    pub fn fromHex(hex: u32) RGBA {
        return .{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
            .a = 1.0,
        };
    }

    /// Create a color with alpha
    pub fn rgba(r: u8, g: u8, b: u8, a: f64) RGBA {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Predefined colors for highlighting
    pub const content_default = RGBA.rgba(111, 168, 220, 0.66);
    pub const padding_default = RGBA.rgba(147, 196, 125, 0.55);
    pub const border_default = RGBA.rgba(255, 229, 153, 0.66);
    pub const margin_default = RGBA.rgba(246, 178, 107, 0.66);
};

/// Highlight configuration
pub const HighlightConfig = struct {
    show_info: ?bool = null,
    show_styles: ?bool = null,
    show_rulers: ?bool = null,
    show_accessibility_info: ?bool = null,
    show_extension_lines: ?bool = null,
    content_color: ?RGBA = null,
    padding_color: ?RGBA = null,
    border_color: ?RGBA = null,
    margin_color: ?RGBA = null,
    event_target_color: ?RGBA = null,
    shape_color: ?RGBA = null,
    shape_margin_color: ?RGBA = null,
    css_grid_color: ?RGBA = null,

    /// Default highlight config with nice colors
    pub fn default() HighlightConfig {
        return .{
            .show_info = true,
            .content_color = RGBA.content_default,
            .padding_color = RGBA.padding_default,
            .border_color = RGBA.border_default,
            .margin_color = RGBA.margin_default,
        };
    }
};

/// Source order highlight configuration
pub const SourceOrderConfig = struct {
    parent_outline_color: ?RGBA = null,
    child_outline_color: ?RGBA = null,
};

/// Scroll snap highlight configuration
pub const ScrollSnapHighlightConfig = struct {
    scroll_snap_container_highlight_config: ScrollSnapContainerHighlightConfig,
    node_id: i64,
};

/// Scroll snap container highlight config
pub const ScrollSnapContainerHighlightConfig = struct {
    snap_port_border: ?LineStyle = null,
    snap_area_border: ?LineStyle = null,
    scroll_margin_color: ?RGBA = null,
    scroll_padding_color: ?RGBA = null,
};

/// Line style for borders
pub const LineStyle = struct {
    color: ?RGBA = null,
    pattern: ?[]const u8 = null, // "dashed" or "dotted"
};
