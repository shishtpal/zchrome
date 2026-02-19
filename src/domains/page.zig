const std = @import("std");
const Session = @import("../core/session.zig").Session;
const Event = @import("../core/protocol.zig").Event;
const json_util = @import("../util/json.zig");

/// Frame identifier
pub const FrameId = []const u8;

/// Frame information
pub const Frame = struct {
    id: FrameId,
    parent_id: ?FrameId = null,
    loader_id: []const u8,
    name: ?[]const u8 = null,
    url: []const u8,
    security_origin: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,

    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.parent_id) |id| allocator.free(id);
        allocator.free(self.loader_id);
        if (self.name) |n| allocator.free(n);
        allocator.free(self.url);
        if (self.security_origin) |o| allocator.free(o);
        if (self.mime_type) |m| allocator.free(m);
    }
};

/// Result of Page.navigate
pub const NavigateResult = struct {
    frame_id: FrameId,
    loader_id: ?[]const u8 = null,
    error_text: ?[]const u8 = null,

    pub fn deinit(self: *NavigateResult, allocator: std.mem.Allocator) void {
        allocator.free(self.frame_id);
        if (self.loader_id) |id| allocator.free(id);
        if (self.error_text) |t| allocator.free(t);
    }
};

/// Screenshot format
pub const ScreenshotFormat = enum {
    jpeg,
    png,
    webp,
};

/// Viewport for screenshot clipping
pub const Viewport = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    scale: f64 = 1.0,
};

/// Screenshot capture parameters
pub const CaptureScreenshotParams = struct {
    format: ?ScreenshotFormat = null,
    quality: ?i32 = null, // For JPEG, 0-100
    clip: ?Viewport = null,
    from_surface: ?bool = null,
    capture_beyond_viewport: ?bool = null,
};

/// Print to PDF parameters
pub const PrintToPDFParams = struct {
    landscape: ?bool = null,
    display_header_footer: ?bool = null,
    print_background: ?bool = null,
    scale: ?f64 = null,
    paper_width: ?f64 = null,
    paper_height: ?f64 = null,
    margin_top: ?f64 = null,
    margin_bottom: ?f64 = null,
    margin_left: ?f64 = null,
    margin_right: ?f64 = null,
    page_ranges: ?[]const u8 = null,
    header_template: ?[]const u8 = null,
    footer_template: ?[]const u8 = null,
    prefer_css_page_size: ?bool = null,
};

/// Page domain client
pub const Page = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable page domain
    pub fn enable(self: *Self) !void {
        _ = try self.session.sendCommand("Page.enable", .{});
    }

    /// Disable page domain
    pub fn disable(self: *Self) !void {
        _ = try self.session.sendCommand("Page.disable", .{});
    }

    /// Navigate to a URL
    pub fn navigate(self: *Self, allocator: std.mem.Allocator, url: []const u8) !NavigateResult {
        const result = try self.session.sendCommand("Page.navigate", .{
            .url = url,
        });

        return .{
            .frame_id = try allocator.dupe(u8, try json_util.getString(result, "frameId")),
            .loader_id = if (result.object.get("loaderId")) |v|
                try allocator.dupe(u8, v.string)
            else
                null,
            .error_text = if (result.object.get("errorText")) |v|
                try allocator.dupe(u8, v.string)
            else
                null,
        };
    }

    /// Reload the page
    pub fn reload(self: *Self, ignore_cache: ?bool) !void {
        _ = try self.session.sendCommand("Page.reload", .{
            .ignore_cache = ignore_cache,
        });
    }

    /// Stop loading
    pub fn stopLoading(self: *Self) !void {
        _ = try self.session.sendCommand("Page.stopLoading", .{});
    }

    /// Capture a screenshot
    pub fn captureScreenshot(self: *Self, allocator: std.mem.Allocator, params: CaptureScreenshotParams) ![]const u8 {
        const result = try self.session.sendCommand("Page.captureScreenshot", params);
        const data = try json_util.getString(result, "data");
        return allocator.dupe(u8, data);
    }

    /// Print to PDF
    pub fn printToPDF(self: *Self, allocator: std.mem.Allocator, params: PrintToPDFParams) ![]const u8 {
        const result = try self.session.sendCommand("Page.printToPDF", params);
        const data = try json_util.getString(result, "data");
        return allocator.dupe(u8, data);
    }

    /// Get the frame tree
    pub fn getFrameTree(self: *Self) !std.json.Value {
        return try self.session.sendCommand("Page.getFrameTree", .{});
    }

    /// Get the main frame
    pub fn getMainFrame(self: *Self, allocator: std.mem.Allocator) !Frame {
        const result = try self.session.sendCommand("Page.getFrameTree", .{});

        const frame_tree = result.object.get("frameTree") orelse return error.MissingField;
        const frame = frame_tree.object.get("frame") orelse return error.MissingField;

        return .{
            .id = try allocator.dupe(u8, try json_util.getString(frame, "id")),
            .parent_id = if (frame.object.get("parentId")) |v|
                try allocator.dupe(u8, v.string)
            else
                null,
            .loader_id = try allocator.dupe(u8, try json_util.getString(frame, "loaderId")),
            .name = if (frame.object.get("name")) |v|
                try allocator.dupe(u8, v.string)
            else
                null,
            .url = try allocator.dupe(u8, try json_util.getString(frame, "url")),
            .security_origin = if (frame.object.get("securityOrigin")) |v|
                try allocator.dupe(u8, v.string)
            else
                null,
            .mime_type = if (frame.object.get("mimeType")) |v|
                try allocator.dupe(u8, v.string)
            else
                null,
        };
    }

    /// Set lifecycle events enabled
    pub fn setLifecycleEventsEnabled(self: *Self, enabled: bool) !void {
        _ = try self.session.sendCommand("Page.setLifecycleEventsEnabled", .{
            .enabled = enabled,
        });
    }

    /// Add a script to evaluate on new document
    pub fn addScriptToEvaluateOnNewDocument(self: *Self, source: []const u8) ![]const u8 {
        const result = try self.session.sendCommand("Page.addScriptToEvaluateOnNewDocument", .{
            .source = source,
        });
        return try json_util.getString(result, "identifier");
    }

    /// Remove script to evaluate on new document
    pub fn removeScriptToEvaluateOnNewDocument(self: *Self, identifier: []const u8) !void {
        _ = try self.session.sendCommand("Page.removeScriptToEvaluateOnNewDocument", .{
            .identifier = identifier,
        });
    }

    /// Bring page to front
    pub fn bringToFront(self: *Self) !void {
        _ = try self.session.sendCommand("Page.bringToFront", .{});
    }

    /// Set document content
    pub fn setDocumentContent(self: *Self, html: []const u8) !void {
        _ = try self.session.sendCommand("Page.setDocumentContent", .{
            .html = html,
        });
    }
};

// ─── Event Types ────────────────────────────────────────────────────────────

pub const LoadEventFired = struct {
    timestamp: f64,
};

pub const DomContentEventFired = struct {
    timestamp: f64,
};

pub const FrameNavigated = struct {
    frame: Frame,
};

pub const FrameStartedLoading = struct {
    frame_id: FrameId,
};

pub const FrameStoppedLoading = struct {
    frame_id: FrameId,
};

pub const FrameAttached = struct {
    frame_id: FrameId,
    parent_frame_id: FrameId,
    stack: ?struct {
        call_frames: []const u8,
    } = null,
};

pub const FrameDetached = struct {
    frame_id: FrameId,
    reason: []const u8,
};

pub const LifecycleEvent = struct {
    frame_id: FrameId,
    name: []const u8,
    timestamp: f64,
};
