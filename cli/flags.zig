//! Unified command-level flag parsing for CLI and REPL.
//!
//! This module provides a single source of truth for parsing command flags like
//! snapshot options (-i, -c, -d), wait options (--text, --match), click options (--js),
//! replay options (--retries), etc.
//!
//! Both CLI (args.zig) and REPL (interactive/commands.zig) use this module,
//! eliminating duplicate parsing code and ensuring feature parity.

const std = @import("std");

/// All command-level flags parsed from tokens.
/// Designed to map directly to CommandCtx fields.
pub const ParsedFlags = struct {
    // Snapshot options
    snap_interactive: bool = false,
    snap_compact: bool = false,
    snap_depth: ?usize = null,
    snap_selector: ?[]const u8 = null,
    snap_mark: bool = false,

    // Wait options
    wait_text: ?[]const u8 = null,
    wait_url: ?[]const u8 = null,
    wait_load: ?[]const u8 = null,
    wait_fn: ?[]const u8 = null,
    wait_media_playing: ?[]const u8 = null,
    wait_media_ended: ?[]const u8 = null,
    wait_media_ready: ?[]const u8 = null,
    wait_media_error: ?[]const u8 = null,

    // Output options
    output: ?[]const u8 = null,
    full_page: bool = false,

    // Click options
    click_js: bool = false,

    // Replay options
    replay_retries: u32 = 3,
    replay_retry_delay: u32 = 100,
    replay_fallback: ?[]const u8 = null,
    replay_resume: bool = false,
    replay_from: ?usize = null,

    // DOM options
    extract_all: bool = false,

    // Remaining positional args (non-flag tokens)
    positional: []const []const u8 = &.{},

    // Tracks which strings were allocated (for deinit)
    _allocated: std.ArrayListUnmanaged([]const u8) = .empty,

    /// Free all allocated strings and the positional slice.
    pub fn deinit(self: *ParsedFlags, allocator: std.mem.Allocator) void {
        for (self._allocated.items) |s| allocator.free(s);
        self._allocated.deinit(allocator);
        allocator.free(self.positional);
    }
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn dupeAndTrack(allocator: std.mem.Allocator, result: *ParsedFlags, s: []const u8) ![]const u8 {
    const duped = try allocator.dupe(u8, s);
    try result._allocated.append(allocator, duped);
    return duped;
}

/// Handle optional value (for --media-* flags).
/// Returns the value if next token is not a flag, otherwise returns empty string.
/// Uses double-dash check so selectors starting with `-` (e.g. `-webkit-*`) are accepted.
fn parseOptionalValue(allocator: std.mem.Allocator, result: *ParsedFlags, tokens: []const []const u8, i: *usize) ![]const u8 {
    if (i.* + 1 < tokens.len) {
        const next = tokens[i.* + 1];
        if (!std.mem.startsWith(u8, next, "--")) {
            i.* += 1;
            return try dupeAndTrack(allocator, result, next);
        }
    }
    return try dupeAndTrack(allocator, result, "");
}

/// Parse command-level flags from a token slice.
/// Works identically whether tokens come from OS args or REPL tokenizer.
///
/// Caller owns the returned ParsedFlags and must either:
/// 1. Call deinit() to free all allocations, OR
/// 2. Transfer ownership by copying fields to CommandCtx and calling takeAllocated()
pub fn parseCommandFlags(allocator: std.mem.Allocator, tokens: []const []const u8) !ParsedFlags {
    var result = ParsedFlags{};
    errdefer result.deinit(allocator);

    var positional: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer positional.deinit(allocator);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];

        // Skip empty tokens
        if (token.len == 0) continue;

        // Check if it's a flag
        if (token[0] == '-') {
            if (try parseFlag(allocator, &result, tokens, &i)) {
                continue;
            }
        }

        // Not a recognized flag - treat as positional
        try positional.append(allocator, token);
    }

    result.positional = try positional.toOwnedSlice(allocator);
    return result;
}

fn parseFlag(allocator: std.mem.Allocator, result: *ParsedFlags, tokens: []const []const u8, i: *usize) !bool {
    const token = tokens[i.*];

    // ─── Snapshot flags ───────────────────────────────────────────────────────
    if (eql(token, "-i") or eql(token, "--interactive-only")) {
        result.snap_interactive = true;
        return true;
    }
    if (eql(token, "-c") or eql(token, "--compact")) {
        result.snap_compact = true;
        return true;
    }
    if (eql(token, "-m") or eql(token, "--mark")) {
        result.snap_mark = true;
        return true;
    }
    if (eql(token, "-d") or eql(token, "--depth")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.snap_depth = std.fmt.parseInt(usize, tokens[i.*], 10) catch null;
        }
        return true;
    }
    if (eql(token, "-s") or eql(token, "--selector")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.snap_selector = try dupeAndTrack(allocator, result, tokens[i.*]);
        }
        return true;
    }

    // ─── Wait flags ───────────────────────────────────────────────────────────
    if (eql(token, "--text")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.wait_text = try dupeAndTrack(allocator, result, tokens[i.*]);
        }
        return true;
    }
    if (eql(token, "--match")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.wait_url = try dupeAndTrack(allocator, result, tokens[i.*]);
        }
        return true;
    }
    if (eql(token, "--load")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.wait_load = try dupeAndTrack(allocator, result, tokens[i.*]);
        }
        return true;
    }
    if (eql(token, "--fn")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.wait_fn = try dupeAndTrack(allocator, result, tokens[i.*]);
        }
        return true;
    }

    // ─── Media wait flags (optional selector) ─────────────────────────────────
    if (eql(token, "--media-playing")) {
        result.wait_media_playing = try parseOptionalValue(allocator, result, tokens, i);
        return true;
    }
    if (eql(token, "--media-ended")) {
        result.wait_media_ended = try parseOptionalValue(allocator, result, tokens, i);
        return true;
    }
    if (eql(token, "--media-ready")) {
        result.wait_media_ready = try parseOptionalValue(allocator, result, tokens, i);
        return true;
    }
    if (eql(token, "--media-error")) {
        result.wait_media_error = try parseOptionalValue(allocator, result, tokens, i);
        return true;
    }

    // ─── Output flags ─────────────────────────────────────────────────────────
    if (eql(token, "-o") or eql(token, "--output")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.output = try dupeAndTrack(allocator, result, tokens[i.*]);
        }
        return true;
    }
    if (eql(token, "--full")) {
        result.full_page = true;
        return true;
    }

    // ─── Click flags ──────────────────────────────────────────────────────────
    if (eql(token, "--js")) {
        result.click_js = true;
        return true;
    }

    // ─── Replay flags ─────────────────────────────────────────────────────────
    if (eql(token, "--retries")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.replay_retries = std.fmt.parseInt(u32, tokens[i.*], 10) catch 3;
        }
        return true;
    }
    if (eql(token, "--retry-delay")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.replay_retry_delay = std.fmt.parseInt(u32, tokens[i.*], 10) catch 100;
        }
        return true;
    }
    if (eql(token, "--fallback")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.replay_fallback = try dupeAndTrack(allocator, result, tokens[i.*]);
        }
        return true;
    }
    if (eql(token, "--resume")) {
        result.replay_resume = true;
        return true;
    }
    if (eql(token, "--from")) {
        if (i.* + 1 < tokens.len) {
            i.* += 1;
            result.replay_from = std.fmt.parseInt(usize, tokens[i.*], 10) catch null;
        }
        return true;
    }

    // ─── DOM flags ────────────────────────────────────────────────────────────
    if (eql(token, "-a") or eql(token, "--all")) {
        result.extract_all = true;
        return true;
    }

    return false;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "parseCommandFlags: snapshot flags" {
    const allocator = std.testing.allocator;
    const tokens = [_][]const u8{ "-i", "-c", "-d", "5", "-s", "#main", "-m" };
    var flags = try parseCommandFlags(allocator, &tokens);
    defer flags.deinit(allocator);

    try std.testing.expect(flags.snap_interactive);
    try std.testing.expect(flags.snap_compact);
    try std.testing.expect(flags.snap_mark);
    try std.testing.expectEqual(@as(?usize, 5), flags.snap_depth);
    try std.testing.expectEqualStrings("#main", flags.snap_selector.?);
    try std.testing.expectEqual(@as(usize, 0), flags.positional.len);
}

test "parseCommandFlags: wait flags" {
    const allocator = std.testing.allocator;
    const tokens = [_][]const u8{ "--text", "hello", "--match", "example.com" };
    var flags = try parseCommandFlags(allocator, &tokens);
    defer flags.deinit(allocator);

    try std.testing.expectEqualStrings("hello", flags.wait_text.?);
    try std.testing.expectEqualStrings("example.com", flags.wait_url.?);
}

test "parseCommandFlags: media flags with optional selector" {
    const allocator = std.testing.allocator;

    // With selector
    const tokens1 = [_][]const u8{ "--media-playing", "video#main" };
    var flags1 = try parseCommandFlags(allocator, &tokens1);
    defer flags1.deinit(allocator);
    try std.testing.expectEqualStrings("video#main", flags1.wait_media_playing.?);

    // Without selector (followed by another flag)
    const tokens2 = [_][]const u8{ "--media-playing", "--text", "foo" };
    var flags2 = try parseCommandFlags(allocator, &tokens2);
    defer flags2.deinit(allocator);
    try std.testing.expectEqualStrings("", flags2.wait_media_playing.?);
    try std.testing.expectEqualStrings("foo", flags2.wait_text.?);
}

test "parseCommandFlags: positional args preserved" {
    const allocator = std.testing.allocator;
    const tokens = [_][]const u8{ "#button", "-i", "some-value" };
    var flags = try parseCommandFlags(allocator, &tokens);
    defer flags.deinit(allocator);

    try std.testing.expect(flags.snap_interactive);
    try std.testing.expectEqual(@as(usize, 2), flags.positional.len);
    try std.testing.expectEqualStrings("#button", flags.positional[0]);
    try std.testing.expectEqualStrings("some-value", flags.positional[1]);
}

test "parseCommandFlags: click and replay flags" {
    const allocator = std.testing.allocator;
    const tokens = [_][]const u8{ "--js", "--retries", "5", "--resume" };
    var flags = try parseCommandFlags(allocator, &tokens);
    defer flags.deinit(allocator);

    try std.testing.expect(flags.click_js);
    try std.testing.expectEqual(@as(u32, 5), flags.replay_retries);
    try std.testing.expect(flags.replay_resume);
}
