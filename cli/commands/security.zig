//! Security domain commands.
//!
//! Provides access to security state and certificate handling,
//! including the ability to ignore certificate errors for testing.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");
const types = @import("types.zig");

pub const CommandCtx = types.CommandCtx;

pub fn security(session: *cdp.Session, ctx: CommandCtx) !void {
    // Check for --help flag
    for (ctx.positional) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printSecurityHelp();
            return;
        }
    }

    const args = ctx.positional;

    if (args.len == 0) {
        printSecurityUsage();
        return;
    }

    if (std.mem.eql(u8, args[0], "state")) {
        try stateCmd(session, ctx);
    } else if (std.mem.eql(u8, args[0], "ignore-certs")) {
        try ignoreCertsCmd(session, true);
    } else if (std.mem.eql(u8, args[0], "verify-certs")) {
        try ignoreCertsCmd(session, false);
    } else {
        std.debug.print("Unknown security subcommand: {s}\n", .{args[0]});
        printSecurityUsage();
    }
}

// ─── state ──────────────────────────────────────────────────────────────────

fn stateCmd(session: *cdp.Session, ctx: CommandCtx) !void {
    _ = ctx;
    var sec = cdp.Security.init(session);
    try sec.enable();

    // Get current URL to show context
    var runtime = cdp.Runtime.init(session);
    try runtime.enable();

    const url = runtime.evaluateAs([]const u8, "window.location.href") catch "Unknown";

    std.debug.print("Security State\n", .{});
    std.debug.print("==============\n", .{});
    std.debug.print("URL: {s}\n", .{url});
    std.debug.print("\n", .{});

    // Check if HTTPS
    if (std.mem.startsWith(u8, url, "https://")) {
        std.debug.print("Protocol: HTTPS (secure)\n", .{});
        std.debug.print("Security domain enabled. Security state changes will be reported via events.\n", .{});
    } else if (std.mem.startsWith(u8, url, "http://")) {
        std.debug.print("Protocol: HTTP (insecure)\n", .{});
        std.debug.print("Warning: Connection is not encrypted.\n", .{});
    } else {
        std.debug.print("Protocol: {s}\n", .{url[0..@min(url.len, 10)]});
    }
}

// ─── ignore-certs / verify-certs ────────────────────────────────────────────

fn ignoreCertsCmd(session: *cdp.Session, ignore: bool) !void {
    var sec = cdp.Security.init(session);
    try sec.enable();
    try sec.setIgnoreCertificateErrors(ignore);

    if (ignore) {
        std.debug.print("Certificate errors will now be IGNORED.\n", .{});
        std.debug.print("Warning: This makes connections vulnerable to MITM attacks.\n", .{});
        std.debug.print("Use this only for testing with self-signed certificates.\n", .{});
    } else {
        std.debug.print("Certificate verification ENABLED (default behavior).\n", .{});
        std.debug.print("Invalid certificates will now cause connection failures.\n", .{});
    }
}

// ─── Help ───────────────────────────────────────────────────────────────────

fn printSecurityUsage() void {
    std.debug.print("Usage: security <subcommand>\n", .{});
    std.debug.print("\nSubcommands: state, ignore-certs, verify-certs\n", .{});
    std.debug.print("Use 'security --help' for details.\n", .{});
}

pub fn printSecurityHelp() void {
    const help =
        \\Security Commands
        \\=================
        \\
        \\Manage security state and certificate handling.
        \\
        \\USAGE:
        \\  security <subcommand>
        \\
        \\SUBCOMMANDS:
        \\  state          Show current security state
        \\  ignore-certs   Ignore certificate errors (useful for self-signed certs)
        \\  verify-certs   Enable certificate verification (default behavior)
        \\
        \\EXAMPLES:
        \\  security state
        \\  security ignore-certs    # For testing with self-signed certificates
        \\  security verify-certs    # Restore default certificate checking
        \\
        \\NOTES:
        \\  - Using 'ignore-certs' makes connections vulnerable to MITM attacks
        \\  - Only use 'ignore-certs' for local development/testing
        \\  - Certificate verification is enabled by default
        \\
    ;
    std.debug.print("{s}", .{help});
}
