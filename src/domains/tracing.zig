const std = @import("std");
const json = @import("json");
const Session = @import("../core/session.zig").Session;

/// Tracing domain client for recording Chrome traces
pub const Tracing = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Start trace recording
    pub fn start(self: *Self, opts: StartOptions) !void {
        try self.session.sendCommandIgnoreResult("Tracing.start", .{
            .categories = opts.categories,
            .options = opts.options,
            .bufferUsageReportingInterval = opts.buffer_usage_reporting_interval,
            .transferMode = opts.transfer_mode,
            .streamFormat = opts.stream_format,
            .streamCompression = opts.stream_compression,
            .traceConfig = opts.trace_config,
            .perfettoConfig = opts.perfetto_config,
        });
    }

    /// Stop trace recording
    pub fn end(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Tracing.end", .{});
    }

    /// Get current trace buffer usage
    pub fn getCategories(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        const result = try self.session.sendCommand("Tracing.getCategories", .{});

        const categories_arr = try result.getArray("categories");
        var categories: std.ArrayList([]const u8) = .empty;
        errdefer categories.deinit(allocator);

        for (categories_arr) |c| {
            if (c == .string) {
                try categories.append(allocator, try allocator.dupe(u8, c.string));
            }
        }

        return categories.toOwnedSlice(allocator);
    }

    /// Request memory dump during tracing
    pub fn requestMemoryDump(self: *Self, deterministic: ?bool, level_of_detail: ?[]const u8) !MemoryDumpResult {
        const result = try self.session.sendCommand("Tracing.requestMemoryDump", .{
            .deterministic = deterministic,
            .levelOfDetail = level_of_detail,
        });

        return .{
            .dump_guid = try result.getString("dumpGuid"),
            .success = try result.getBool("success"),
        };
    }

    /// Record clock sync marker
    pub fn recordClockSyncMarker(self: *Self, sync_id: []const u8) !void {
        try self.session.sendCommandIgnoreResult("Tracing.recordClockSyncMarker", .{
            .syncId = sync_id,
        });
    }
};

/// Options for starting trace
pub const StartOptions = struct {
    categories: ?[]const u8 = null,
    options: ?[]const u8 = null,
    buffer_usage_reporting_interval: ?f64 = null,
    transfer_mode: ?[]const u8 = null, // "ReportEvents" or "ReturnAsStream"
    stream_format: ?[]const u8 = null, // "json" or "proto"
    stream_compression: ?[]const u8 = null, // "none" or "gzip"
    trace_config: ?TraceConfig = null,
    perfetto_config: ?[]const u8 = null,
};

/// Trace configuration
pub const TraceConfig = struct {
    record_mode: ?[]const u8 = null,
    enable_sampling: ?bool = null,
    enable_systrace: ?bool = null,
    enable_argument_filter: ?bool = null,
    included_categories: ?[]const []const u8 = null,
    excluded_categories: ?[]const []const u8 = null,
    synthetic_delays: ?[]const []const u8 = null,
    memory_dump_config: ?MemoryDumpConfig = null,
};

/// Memory dump configuration
pub const MemoryDumpConfig = struct {
    triggers: ?[]const MemoryDumpTrigger = null,
};

/// Memory dump trigger
pub const MemoryDumpTrigger = struct {
    mode: []const u8,
    periodic_interval_ms: ?u32 = null,
};

/// Memory dump result
pub const MemoryDumpResult = struct {
    dump_guid: []const u8,
    success: bool,
};

// ─── Event Types ────────────────────────────────────────────────────────────

/// Sent when trace buffer usage changes
pub const BufferUsage = struct {
    percent_full: ?f64 = null,
    event_count: ?f64 = null,
    value: ?f64 = null,
};

/// Contains a bucket of trace events
pub const DataCollected = struct {
    value: []json.Value,
};

/// Signals tracing is complete
pub const TracingComplete = struct {
    data_loss_occurred: bool,
    stream: ?[]const u8 = null,
    trace_format: ?[]const u8 = null,
    stream_compression: ?[]const u8 = null,
};
