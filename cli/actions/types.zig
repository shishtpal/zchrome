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

    pub fn deinit(self: *ResolvedElement) void {
        if (self.css_selector) |s| self.allocator.free(s);
        if (self.role) |r| self.allocator.free(r);
        if (self.name) |n| self.allocator.free(n);
    }
};

/// Element position
pub const ElementPosition = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};
