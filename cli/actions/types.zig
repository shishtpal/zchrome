const std = @import("std");

/// Resolved element information
pub const ResolvedElement = struct {
    /// CSS selector or null if using JS-based resolution
    css_selector: ?[]const u8,
    /// Role for JS-based resolution (from snapshot ref)
    role: ?[]const u8,
    /// Name for JS-based resolution (from snapshot ref)
    name: ?[]const u8,
    /// Nth index for disambiguation
    nth: ?usize,
    allocator: std.mem.Allocator,

    // Deep selector context (for >>> piercing)
    /// JS expression evaluating to root node (e.g., "document.querySelector('my-comp').shadowRoot")
    root_expression: ?[]const u8 = null,
    /// Execution context ID for iframe targeting (Phase 2)
    context_id: ?i64 = null,
    /// Viewport offsets for iframe coordinate adjustment (Phase 2)
    iframe_offsets: ?struct { x: f64, y: f64 } = null,

    pub fn deinit(self: *ResolvedElement) void {
        if (self.css_selector) |s| self.allocator.free(s);
        if (self.role) |r| self.allocator.free(r);
        if (self.name) |n| self.allocator.free(n);
        if (self.root_expression) |r| self.allocator.free(r);
    }
};

/// Element position
pub const ElementPosition = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};
