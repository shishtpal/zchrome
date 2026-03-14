const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─── JSON Module (from zlib-json) ────────────────────────
    const json_dep = b.dependency("zlib_json", .{
        .target = target,
        .optimize = optimize,
    });
    const json_mod = json_dep.module("json");

    // ─── PNG Module (from zlib-png) ────────────────────────────
    const png_dep = b.dependency("zlib_png", .{
        .target = target,
        .optimize = optimize,
    });
    const png_mod = png_dep.module("png");

    // ─── WebSocket Module (from zlib-wss) ──────────────────────
    const wss_dep = b.dependency("zlib_wss", .{
        .target = target,
        .optimize = optimize,
    });
    const wss_mod = wss_dep.module("zlib_wss");

    // ─── HTTP Module (from zlib-http) ─────────────────────────
    const http_dep = b.dependency("zlib_http", .{
        .target = target,
        .optimize = optimize,
    });
    const http_mod = http_dep.module("zlib-http");

    // ─── Clipboard Module (from zlib_clipboard) ──────────────
    const clipboard_dep = b.dependency("zlib_clipboard", .{
        .target = target,
        .optimize = optimize,
    });
    const clipboard_mod = clipboard_dep.module("zlib_clipboard");

    // ─── Library Module ──────────────────────────────────────
    const cdp_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    cdp_mod.addImport("json", json_mod);
    cdp_mod.addImport("wss", wss_mod);
    cdp_mod.addImport("zhttp", http_mod);

    // ─── CLI Executable ──────────────────────────────────────
    const cli_mod = b.createModule(.{
        .root_source_file = b.path("cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_mod.addImport("cdp", cdp_mod);
    cli_mod.addImport("json", json_mod);
    cli_mod.addImport("png", png_mod);
    cli_mod.addImport("wss", wss_mod);
    cli_mod.addImport("clipboard", clipboard_mod);

    const cli = b.addExecutable(.{
        .name = "zchrome",
        .root_module = cli_mod,
    });
    b.installArtifact(cli);

    const run_cmd = b.addRunArtifact(cli);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the CDP CLI demo");
    run_step.dependOn(&run_cmd.step);

    // ─── Unit Tests ──────────────────────────────────────────
    const test_files = [_][]const u8{
        "tests/test_json.zig",
        "tests/test_protocol.zig",
        "tests/test_websocket.zig",
        "tests/test_connection.zig",
        "tests/test_launcher.zig",
        "tests/test_session.zig",
        "tests/test_domains_page.zig",
        "tests/test_domains_runtime.zig",
        "tests/test_domains_network.zig",
        "tests/test_domains_dom.zig",
        "tests/test_domains_target.zig",
        // New comprehensive tests
        "tests/test_helpers.zig",
        "tests/test_config.zig",
        "tests/test_snapshot.zig",
    };

    const test_step = b.step("test", "Run unit tests");

    for (test_files) |test_file| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("cdp", cdp_mod);
        test_mod.addImport("json", json_mod);

        const t = b.addTest(.{
            .root_module = test_mod,
        });
        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }

    // ─── Integration Tests (requires Chrome) ─────────────────
    const integration_mod = b.createModule(.{
        .root_source_file = b.path("tests/test_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_mod.addImport("cdp", cdp_mod);
    integration_mod.addImport("json", json_mod);

    const integration_test = b.addTest(.{
        .root_module = integration_mod,
    });
    const run_integration = b.addRunArtifact(integration_test);

    const integration_step = b.step("test-integration", "Run integration tests (requires Chrome)");
    integration_step.dependOn(&run_integration.step);
}
