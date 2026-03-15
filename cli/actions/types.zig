const std = @import("std");
const cdp = @import("cdp");

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

    // OOP iframe support (Phase 3)
    /// Session for OOP iframe (if element is inside a cross-origin iframe)
    frame_session: ?*cdp.Session = null,
    /// Session ID for cleanup (we own this session and must detach)
    frame_session_id: ?[]const u8 = null,
    /// Connection reference for detaching (if we own a frame session)
    connection: ?*cdp.Connection = null,

    pub fn deinit(self: *ResolvedElement) void {
        if (self.css_selector) |s| self.allocator.free(s);
        if (self.role) |r| self.allocator.free(r);
        if (self.name) |n| self.allocator.free(n);
        if (self.root_expression) |r| self.allocator.free(r);

        // Detach from OOP iframe session if we own it
        if (self.frame_session_id) |session_id| {
            if (self.connection) |conn| {
                var target = cdp.Target.init(conn);
                target.detachFromTarget(session_id) catch {};
            }
            self.allocator.free(session_id);
        }
        // Note: frame_session is owned by connection, don't free it
    }

    /// Get the effective session to use for CDP commands
    pub fn getEffectiveSession(self: *const ResolvedElement, default_session: *cdp.Session) *cdp.Session {
        return self.frame_session orelse default_session;
    }
};

/// Element position
pub const ElementPosition = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};
