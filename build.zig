const std = @import("std");

fn createDepModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, dep_name: []const u8, mod_name: []const u8) *std.Build.Module {
    const dep = b.dependency(dep_name, .{
        .target = target,
        .optimize = optimize,
    });
    return dep.module(mod_name);
}

fn createModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, root_source: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(root_source),
        .target = target,
        .optimize = optimize,
    });
}

fn addModuleImports(mod: *std.Build.Module, imports: []const struct { name: []const u8, mod: *std.Build.Module }) void {
    for (imports) |imp| {
        mod.addImport(imp.name, imp.mod);
    }
}

fn createTest(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, test_file: []const u8, cdp_mod: *std.Build.Module, json_mod: *std.Build.Module) *std.Build.Step.Run {
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
    return b.addRunArtifact(t);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const json_mod = createDepModule(b, target, optimize, "zlib_json", "zlib_json");
    const png_mod = createDepModule(b, target, optimize, "zlib_png", "png");
    const wss_mod = createDepModule(b, target, optimize, "zlib_wss", "zlib_wss");
    const http_mod = createDepModule(b, target, optimize, "zlib_http", "zlib_http");
    const clipboard_mod = createDepModule(b, target, optimize, "zlib_clipboard", "zlib_clipboard");

    const cdp_mod = createModule(b, target, optimize, "src/root.zig");
    addModuleImports(cdp_mod, &.{
        .{ .name = "json", .mod = json_mod },
        .{ .name = "wss", .mod = wss_mod },
        .{ .name = "zhttp", .mod = http_mod },
    });

    const cli_mod = createModule(b, target, optimize, "cli/main.zig");
    addModuleImports(cli_mod, &.{
        .{ .name = "cdp", .mod = cdp_mod },
        .{ .name = "json", .mod = json_mod },
        .{ .name = "png", .mod = png_mod },
        .{ .name = "wss", .mod = wss_mod },
        .{ .name = "clipboard", .mod = clipboard_mod },
    });

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
        "tests/test_domains_security.zig",
        "tests/test_domains_css.zig",
        "tests/test_domains_debugger.zig",
        "tests/test_helpers.zig",
        "tests/test_config.zig",
        "tests/test_snapshot.zig",
    };

    const test_step = b.step("test", "Run unit tests");

    for (test_files) |test_file| {
        const run_t = createTest(b, target, optimize, test_file, cdp_mod, json_mod);
        test_step.dependOn(&run_t.step);
    }

    const run_integration = createTest(b, target, optimize, "tests/test_integration.zig", cdp_mod, json_mod);

    const integration_step = b.step("test-integration", "Run integration tests (requires Chrome)");
    integration_step.dependOn(&run_integration.step);
}
