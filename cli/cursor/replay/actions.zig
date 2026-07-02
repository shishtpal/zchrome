//! Per-action handlers for macro replay.
//!
//! Each action type (click, fill, extract, etc.) has its own handler function.

const std = @import("std");
const json = @import("json");
const cdp = @import("cdp");

// Local imports
const macro = @import("../macro/mod.zig");
const state = @import("../state.zig");
const utils = @import("../utils.zig");
const cursor_actions = @import("../actions.zig");
const video = @import("../video/mod.zig");

// Command imports
const types = @import("../../commands/types.zig");
const elements = @import("../../commands/elements.zig");
const keyboard = @import("../../commands/keyboard.zig");
const scroll_mod = @import("../../commands/scroll.zig");
const wait_mod = @import("../../commands/wait.zig");
const navigation = @import("../../commands/navigation.zig");
const dom_mod = @import("../../commands/dom.zig");

// Local replay imports
const interpolate = @import("interpolate.zig");
const json_utils = @import("json.zig");

pub const CommandCtx = types.CommandCtx;

/// Mark action errors - used to signal explicit status from nested macros
pub const MarkError = error{
    MarkSuccess,
    MarkFailed,
    MarkSkipped,
};

/// Forward declaration for ReplayOptions (defined in cli.zig)
pub const ReplayOptions = @import("cli.zig").ReplayOptions;

/// Context for action execution
pub const ActionContext = struct {
    session: *cdp.Session,
    allocator: std.mem.Allocator,
    io: std.Io,
    variables: *std.StringHashMap(state.VarValue),
    page: *cdp.Page,
    macro_file: []const u8,
    options: ReplayOptions,
    video_orch: ?*video.Orchestrator,
    call_stack: *std.ArrayList([]const u8),
};

/// Execute a command based on action type
pub fn executeCommand(ctx: ActionContext, cmd: macro.MacroCommand) anyerror!void {
    switch (cmd.action) {
        .click => executeClick(ctx, cmd),
        .dblclick => executeDblclick(ctx, cmd),
        .fill => executeFill(ctx, cmd),
        .type => executeType(ctx, cmd),
        .check => executeCheck(ctx, cmd),
        .uncheck => executeUncheck(ctx, cmd),
        .select => executeSelect(ctx, cmd),
        .multiselect => executeMultiselect(ctx, cmd),
        .press => executePress(ctx, cmd),
        .hover => executeHover(ctx, cmd),
        .scroll => executeScroll(ctx, cmd),
        .navigate => executeNavigate(ctx, cmd),
        .wait => executeWait(ctx, cmd),
        .assert => {}, // Handled in executor
        .extract => executeExtract(ctx, cmd),
        .dialog => executeDialog(ctx, cmd),
        .upload => executeUpload(ctx, cmd),
        .goto => try executeGoto(ctx, cmd),
        .capture => executeCapture(ctx, cmd),
        .load => executeLoad(ctx, cmd),
        .foreach => try executeForeach(ctx, cmd),
        .mark => return executeMark(cmd),
        .@"if" => try executeIf(ctx, cmd),
        .repeat => try executeRepeat(ctx, cmd),
    }
}

fn executeClick(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectors(ctx.session, ctx.allocator, ctx.io, cmd, elements.click);
}

fn executeDblclick(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectors(ctx.session, ctx.allocator, ctx.io, cmd, elements.dblclick);
}

fn executeFill(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectorsFill(ctx.session, ctx.allocator, ctx.io, cmd);
}

fn executeType(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectorsType(ctx.session, ctx.allocator, ctx.io, cmd);
}

fn executeCheck(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectors(ctx.session, ctx.allocator, ctx.io, cmd, elements.check);
}

fn executeUncheck(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectors(ctx.session, ctx.allocator, ctx.io, cmd, elements.uncheck);
}

fn executeSelect(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectorsSelect(ctx.session, ctx.allocator, ctx.io, cmd);
}

fn executeMultiselect(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectorsMultiselect(ctx.session, ctx.allocator, ctx.io, cmd);
}

fn executePress(ctx: ActionContext, cmd: macro.MacroCommand) void {
    if (cmd.key) |key| {
        var key_args: [1][]const u8 = .{key};
        const key_ctx = types.CommandCtx{
            .allocator = ctx.allocator,
            .io = ctx.io,
            .positional = &key_args,
        };
        keyboard.press(ctx.session, key_ctx) catch |err| {
            std.debug.print("    Error: {}\n", .{err});
        };
    }
}

fn executeHover(ctx: ActionContext, cmd: macro.MacroCommand) void {
    cursor_actions.tryWithFallbackSelectors(ctx.session, ctx.allocator, ctx.io, cmd, elements.hover);
}

fn executeScroll(ctx: ActionContext, cmd: macro.MacroCommand) void {
    if (cmd.scroll_y) |sy| {
        const direction: []const u8 = if (sy > 0) "down" else "up";
        const amount = if (sy > 0) sy else -sy;
        var scroll_buf: [16]u8 = undefined;
        const amount_str = std.fmt.bufPrint(&scroll_buf, "{}", .{amount}) catch "300";
        var scroll_args: [2][]const u8 = .{ direction, amount_str };
        const scroll_ctx = types.CommandCtx{
            .allocator = ctx.allocator,
            .io = ctx.io,
            .positional = &scroll_args,
        };
        scroll_mod.scroll(ctx.session, scroll_ctx) catch |err| {
            std.debug.print("    Error: {}\n", .{err});
        };
    }
}

fn executeNavigate(ctx: ActionContext, cmd: macro.MacroCommand) void {
    if (cmd.value) |url| {
        // Interpolate variables in URL
        const interpolated_url = interpolate.interpolateVariables(ctx.allocator, url, ctx.variables);
        defer if (interpolated_url) |u| ctx.allocator.free(u);
        const final_url = interpolated_url orelse url;

        var nav_args: [1][]const u8 = .{final_url};
        const nav_ctx = types.CommandCtx{
            .allocator = ctx.allocator,
            .io = ctx.io,
            .positional = &nav_args,
        };
        navigation.navigate(ctx.session, nav_ctx) catch |err| {
            std.debug.print("    Error: {}\n", .{err});
        };
    }
}

fn executeWait(ctx: ActionContext, cmd: macro.MacroCommand) void {
    if (cmd.selectors != null or cmd.selector != null) {
        const selectors = cmd.selectors orelse if (cmd.selector) |sel| blk: {
            var single: [1][]const u8 = .{sel};
            break :blk &single;
        } else &.{};

        for (selectors, 0..) |sel, idx| {
            var wait_args: [1][]const u8 = .{sel};
            const wait_ctx = types.CommandCtx{
                .allocator = ctx.allocator,
                .io = ctx.io,
                .positional = &wait_args,
            };
            wait_mod.wait(ctx.session, wait_ctx) catch |err| {
                if (idx + 1 < selectors.len) {
                    std.debug.print("    (trying fallback selector...)\n", .{});
                    continue;
                }
                std.debug.print("    Error: {}\n", .{err});
                break;
            };
            break;
        }
    } else if (cmd.value) |val| {
        if (std.fmt.parseInt(u32, val, 10)) |ms| {
            std.debug.print(" ({}ms)", .{ms});
            utils.waitForTime(ms);
        } else |_| {
            const wait_ctx = types.CommandCtx{
                .allocator = ctx.allocator,
                .io = ctx.io,
                .positional = &.{},
                .wait_text = val,
            };
            wait_mod.wait(ctx.session, wait_ctx) catch |err| {
                std.debug.print("    Error: {}\n", .{err});
            };
        }
    }
}

fn executeExtract(ctx: ActionContext, cmd: macro.MacroCommand) void {
    const raw_output = cmd.output orelse {
        std.debug.print("    Error: extract requires output path\n", .{});
        return;
    };
    // Interpolate variables in output path
    const interpolated_output = interpolate.interpolateVariables(ctx.allocator, raw_output, ctx.variables);
    defer if (interpolated_output) |o| ctx.allocator.free(o);
    const output = interpolated_output orelse raw_output;

    const dir = std.Io.Dir.cwd();

    // Check for fields extraction mode first
    if (cmd.fields) |fields_map| {
        const result_json = json_utils.extractFields(ctx.session, ctx.allocator, fields_map, ctx.variables) catch |err| {
            std.debug.print("    Error extracting fields: {}\n", .{err});
            return;
        };
        defer ctx.allocator.free(result_json);

        // Handle append mode
        if (cmd.append orelse false) {
            const final_json = json_utils.appendWithDedupe(ctx.allocator, ctx.io, output, result_json, cmd.dedupe_key) catch |err| {
                std.debug.print("    Error appending: {}\n", .{err});
                return;
            };
            defer ctx.allocator.free(final_json);
            dir.writeFile(ctx.io, .{ .sub_path = output, .data = final_json }) catch |err| {
                std.debug.print("    Error writing: {}\n", .{err});
                return;
            };
            std.debug.print(" -> {s} (appended)\n", .{output});
        } else {
            dir.writeFile(ctx.io, .{ .sub_path = output, .data = result_json }) catch |err| {
                std.debug.print("    Error writing: {}\n", .{err});
                return;
            };
            std.debug.print(" -> {s}\n", .{output});
        }
        return;
    }

    // Standard single-selector extraction
    const selector = cmd.selector orelse {
        std.debug.print("    Error: extract requires selector or fields\n", .{});
        return;
    };
    const mode: dom_mod.ExtractMode = if (cmd.mode) |m|
        std.meta.stringToEnum(dom_mod.ExtractMode, m) orelse .dom
    else
        .dom;
    const result_json = dom_mod.executeExtract(ctx.session, ctx.allocator, selector, mode, cmd.extract_all orelse false) catch |err| {
        std.debug.print("    Error: {}\n", .{err});
        return;
    };
    defer ctx.allocator.free(result_json);

    // Handle append mode with optional deduplication
    if (cmd.append orelse false) {
        const final_json = json_utils.appendWithDedupe(ctx.allocator, ctx.io, output, result_json, cmd.dedupe_key) catch |err| {
            std.debug.print("    Error appending: {}\n", .{err});
            return;
        };
        defer ctx.allocator.free(final_json);
        dir.writeFile(ctx.io, .{ .sub_path = output, .data = final_json }) catch |err| {
            std.debug.print("    Error writing: {}\n", .{err});
            return;
        };
        // Count items added
        var new_parsed = json.parse(ctx.allocator, result_json, .{}) catch null;
        var final_parsed = json.parse(ctx.allocator, final_json, .{}) catch null;
        if (new_parsed) |*np| {
            defer np.deinit(ctx.allocator);
            if (final_parsed) |*fp| {
                defer fp.deinit(ctx.allocator);
                const new_count = if (np.* == .array) np.array.items.len else 1;
                const final_count = if (fp.* == .array) fp.array.items.len else 1;
                std.debug.print(" -> {s} (appended, {} total, {} new)\n", .{ output, final_count, new_count });
                return;
            }
        }
        std.debug.print(" -> {s} (appended)\n", .{output});
    } else {
        dir.writeFile(ctx.io, .{ .sub_path = output, .data = result_json }) catch |err| {
            std.debug.print("    Error writing: {}\n", .{err});
            return;
        };
        std.debug.print(" -> {s}\n", .{output});
    }
}

fn executeDialog(ctx: ActionContext, cmd: macro.MacroCommand) void {
    const should_accept = cmd.accept orelse true;
    const timeout_ms = cmd.timeout orelse 5000;
    var dialog_info = ctx.page.waitForJavaScriptDialogOpening(ctx.allocator, timeout_ms) catch |err| {
        std.debug.print("\n    No dialog appeared: {}\n", .{err});
        return;
    };
    defer dialog_info.deinit(ctx.allocator);

    if (cmd.text) |expected_text| {
        const has_wildcard = std.mem.indexOf(u8, expected_text, "*") != null;
        const matches = if (has_wildcard)
            utils.matchesGlobPattern(dialog_info.message, expected_text)
        else
            std.mem.eql(u8, dialog_info.message, expected_text);

        if (!matches) {
            std.debug.print("\n    Dialog message mismatch\n", .{});
            if (has_wildcard) {
                std.debug.print("      Pattern: \"{s}\"\n", .{expected_text});
            } else {
                std.debug.print("      Expected: \"{s}\"\n", .{expected_text});
            }
            std.debug.print("      Actual:  \"{s}\"\n", .{dialog_info.message});
            return;
        }
        std.debug.print(" (message verified)", .{});
    }

    ctx.page.handleJavaScriptDialog(.{
        .accept = should_accept,
        .prompt_text = if (should_accept) cmd.value else null,
    }) catch |err| {
        std.debug.print("\n    Error handling dialog: {}\n", .{err});
        return;
    };

    if (should_accept) {
        if (cmd.value) |v| {
            std.debug.print(" accepted with text: \"{s}\"\n", .{v});
        } else {
            std.debug.print(" accepted\n", .{});
        }
    } else {
        std.debug.print(" dismissed\n", .{});
    }
}

fn executeUpload(ctx: ActionContext, cmd: macro.MacroCommand) void {
    const files = cmd.files orelse {
        std.debug.print("    Error: upload requires files array\n", .{});
        return;
    };
    if (files.len == 0) {
        std.debug.print("    Error: files array is empty\n", .{});
        return;
    }

    // Resolve file paths relative to macro file's directory
    var resolved_files = ctx.allocator.alloc([]const u8, files.len) catch {
        std.debug.print("    Error: failed to allocate resolved files\n", .{});
        return;
    };
    var resolved_count: usize = 0;
    defer {
        for (resolved_files[0..resolved_count]) |f| ctx.allocator.free(f);
        ctx.allocator.free(resolved_files);
    }

    const macro_dir = std.fs.path.dirname(ctx.macro_file);
    for (files) |file| {
        // Check if path is already absolute (Windows drive letter or Unix /)
        const is_absolute = (file.len >= 2 and file[1] == ':') or (file.len >= 1 and file[0] == '/');

        const resolved_path = blk: {
            if (!is_absolute) {
                if (macro_dir) |dir| {
                    const joined = std.fs.path.join(ctx.allocator, &.{ dir, file }) catch break :blk null;
                    break :blk joined;
                }
            }
            break :blk null;
        };
        resolved_files[resolved_count] = resolved_path orelse (ctx.allocator.dupe(u8, file) catch {
            std.debug.print("    Error: failed to dupe file path\n", .{});
            return;
        });
        resolved_count += 1;
    }

    std.debug.print("    Resolved files:\n", .{});
    for (resolved_files[0..resolved_count]) |f| {
        std.debug.print("      - {s}\n", .{f});
    }

    cursor_actions.tryWithFallbackSelectorsUpload(ctx.session, ctx.allocator, ctx.io, cmd, resolved_files);
}

fn executeGoto(ctx: ActionContext, cmd: macro.MacroCommand) anyerror!void {
    const executor = @import("executor.zig");

    const target_file = cmd.file orelse {
        std.debug.print("    Error: goto requires file field\n", .{});
        return;
    };

    // Resolve target file path relative to macro file's directory
    const resolved_path = blk: {
        const macro_dir = std.fs.path.dirname(ctx.macro_file);
        if (macro_dir) |dir| {
            // Try joining with macro's directory first
            const joined = std.fs.path.join(ctx.allocator, &.{ dir, target_file }) catch break :blk target_file;

            // Check if the joined path exists by trying to read it
            const test_dir = std.Io.Dir.cwd();
            var test_buf: [1]u8 = undefined;
            if (test_dir.readFile(ctx.io, joined, &test_buf)) |_| {
                break :blk joined;
            } else |_| {
                // File not found relative to macro dir, try CWD
                ctx.allocator.free(joined);
                break :blk target_file;
            }
        }
        break :blk target_file;
    };
    defer if (resolved_path.ptr != target_file.ptr) ctx.allocator.free(resolved_path);

    std.debug.print(" -> {s}\n", .{resolved_path});

    // Save original values and apply params (temporary override)
    var saved_values: std.StringHashMap(state.VarValue) = std.StringHashMap(state.VarValue).init(ctx.allocator);
    defer {
        // Restore original values
        var iter = saved_values.iterator();
        while (iter.next()) |entry| {
            // Remove the param-set value
            if (ctx.variables.fetchRemove(entry.key_ptr.*)) |old| {
                ctx.allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(ctx.allocator);
            }
            // Restore original value
            const key = ctx.allocator.dupe(u8, entry.key_ptr.*) catch continue;
            const val = entry.value_ptr.clone(ctx.allocator) catch {
                ctx.allocator.free(key);
                continue;
            };
            ctx.variables.put(key, val) catch {
                ctx.allocator.free(key);
                var tmp = val;
                tmp.deinit(ctx.allocator);
            };
        }
        // Clean up saved values
        var save_iter = saved_values.iterator();
        while (save_iter.next()) |entry| {
            entry.value_ptr.deinit(ctx.allocator);
        }
        saved_values.deinit();
    }

    if (cmd.params) |params| {
        for (params.keys(), params.values()) |key, val| {
            // Save original value if exists
            if (ctx.variables.get(key)) |orig| {
                const saved_key = ctx.allocator.dupe(u8, key) catch continue;
                const saved_val = orig.clone(ctx.allocator) catch {
                    ctx.allocator.free(saved_key);
                    continue;
                };
                saved_values.put(saved_key, saved_val) catch {
                    ctx.allocator.free(saved_key);
                    var tmp = saved_val;
                    tmp.deinit(ctx.allocator);
                    continue;
                };
            }

            // Resolve value (if starts with $ it's a variable reference)
            const resolved_val = if (val.len > 0 and val[0] == '$') blk: {
                const var_name = val[1..];
                const var_val = ctx.variables.get(var_name) orelse break :blk val;
                break :blk var_val.asString() orelse val;
            } else val;

            // Set the param value
            const new_key = ctx.allocator.dupe(u8, key) catch continue;
            const new_val = ctx.allocator.dupe(u8, resolved_val) catch {
                ctx.allocator.free(new_key);
                continue;
            };

            // Remove old if exists
            if (ctx.variables.fetchRemove(new_key)) |old| {
                ctx.allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(ctx.allocator);
            }

            ctx.variables.put(new_key, .{ .string = new_val }) catch {
                ctx.allocator.free(new_key);
                ctx.allocator.free(new_val);
            };
        }
    }

    // Check for circular include
    for (ctx.call_stack.items) |stack_file| {
        if (std.mem.eql(u8, stack_file, resolved_path)) {
            std.debug.print("    Error: circular include detected: {s}\n", .{resolved_path});
            return;
        }
    }

    // Pass full options to nested call (preserves interval, retries, video, etc.)
    var nested_options = ctx.options;
    nested_options.video_orch = ctx.video_orch; // Ensure orchestrator is passed
    nested_options.resume_mode = false; // Don't resume nested calls
    nested_options.start_index = null;
    nested_options.variables = ctx.variables;
    nested_options.call_stack = ctx.call_stack;

    var result_status: []const u8 = "success";

    executor.replayCommandsWithOptions(ctx.session, ctx.allocator, ctx.io, resolved_path, nested_options) catch |err| {
        switch (err) {
            error.MarkSuccess => {
                result_status = "success";
                if (cmd.result_as == null) return err;
            },
            error.MarkFailed => {
                result_status = "failed";
                if (cmd.result_as == null) return err;
            },
            error.MarkSkipped => {
                result_status = "skipped";
                if (cmd.result_as == null) return err;
            },
            else => {
                result_status = "failed";
                std.debug.print("    Error replaying {s}: {}\n", .{ resolved_path, err });
            },
        }
    };

    // Capture result status if result_as is set
    if (cmd.result_as) |var_name| {
        const key = ctx.allocator.dupe(u8, var_name) catch return;
        const val = ctx.allocator.dupe(u8, result_status) catch {
            ctx.allocator.free(key);
            return;
        };

        if (ctx.variables.fetchRemove(key)) |old| {
            ctx.allocator.free(old.key);
            var old_val = old.value;
            old_val.deinit(ctx.allocator);
        }

        ctx.variables.put(key, .{ .string = val }) catch {
            ctx.allocator.free(key);
            ctx.allocator.free(val);
        };
        std.debug.print("    {s}={s}\n", .{ var_name, result_status });
    }
}

fn executeCapture(ctx: ActionContext, cmd: macro.MacroCommand) void {
    const selector = cmd.selector orelse {
        std.debug.print("    Error: capture requires selector\n", .{});
        return;
    };
    const escaped_sel = utils.escapeForJs(ctx.allocator, selector) catch |err| {
        std.debug.print("    Error escaping selector: {}\n", .{err});
        return;
    };
    defer ctx.allocator.free(escaped_sel);

    var runtime = cdp.Runtime.init(ctx.session);
    runtime.enable() catch {};

    // count_as: capture element count
    if (cmd.count_as) |var_name| {
        const js = std.fmt.allocPrint(ctx.allocator, "document.querySelectorAll('{s}').length", .{escaped_sel}) catch return;
        defer ctx.allocator.free(js);
        var result = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch return;
        defer result.deinit(ctx.allocator);
        if (result.asNumber()) |num| {
            const int_val: i64 = @intFromFloat(num);
            const key = ctx.allocator.dupe(u8, var_name) catch return;
            if (ctx.variables.fetchRemove(key)) |old| {
                ctx.allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(ctx.allocator);
            }
            ctx.variables.put(key, .{ .int = int_val }) catch {
                ctx.allocator.free(key);
                return;
            };
            std.debug.print(" {s}={}\n", .{ var_name, int_val });
        }
    }
    // text_as: capture text content
    if (cmd.text_as) |var_name| {
        const js = std.fmt.allocPrint(ctx.allocator, "document.querySelector('{s}')?.textContent?.trim()||''", .{escaped_sel}) catch return;
        defer ctx.allocator.free(js);
        var result = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch return;
        defer result.deinit(ctx.allocator);
        if (result.asString()) |str| {
            const key = ctx.allocator.dupe(u8, var_name) catch return;
            const val_str = ctx.allocator.dupe(u8, str) catch {
                ctx.allocator.free(key);
                return;
            };
            if (ctx.variables.fetchRemove(key)) |old| {
                ctx.allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(ctx.allocator);
            }
            ctx.variables.put(key, .{ .string = val_str }) catch {
                ctx.allocator.free(key);
                ctx.allocator.free(val_str);
                return;
            };
            std.debug.print(" {s}=\"{s}\"\n", .{ var_name, str });
        }
    }
    // value_as: capture input value
    if (cmd.value_as) |var_name| {
        const js = std.fmt.allocPrint(ctx.allocator, "document.querySelector('{s}')?.value||''", .{escaped_sel}) catch return;
        defer ctx.allocator.free(js);
        var result = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch return;
        defer result.deinit(ctx.allocator);
        if (result.asString()) |str| {
            const key = ctx.allocator.dupe(u8, var_name) catch return;
            const val_str = ctx.allocator.dupe(u8, str) catch {
                ctx.allocator.free(key);
                return;
            };
            if (ctx.variables.fetchRemove(key)) |old| {
                ctx.allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(ctx.allocator);
            }
            ctx.variables.put(key, .{ .string = val_str }) catch {
                ctx.allocator.free(key);
                ctx.allocator.free(val_str);
                return;
            };
            std.debug.print(" {s}=\"{s}\"\n", .{ var_name, str });
        }
    }
    // attr_as: capture attribute value
    if (cmd.attr_as) |var_name| {
        const attr = cmd.attribute orelse {
            std.debug.print("    Error: attr_as requires attribute field\n", .{});
            return;
        };
        const escaped_attr = utils.escapeForJs(ctx.allocator, attr) catch return;
        defer ctx.allocator.free(escaped_attr);
        const js = std.fmt.allocPrint(ctx.allocator, "document.querySelector('{s}')?.getAttribute('{s}')||''", .{ escaped_sel, escaped_attr }) catch return;
        defer ctx.allocator.free(js);
        var result = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch return;
        defer result.deinit(ctx.allocator);
        if (result.asString()) |str| {
            const key = ctx.allocator.dupe(u8, var_name) catch return;
            const val_str = ctx.allocator.dupe(u8, str) catch {
                ctx.allocator.free(key);
                return;
            };
            if (ctx.variables.fetchRemove(key)) |old| {
                ctx.allocator.free(old.key);
                var old_val = old.value;
                old_val.deinit(ctx.allocator);
            }
            ctx.variables.put(key, .{ .string = val_str }) catch {
                ctx.allocator.free(key);
                ctx.allocator.free(val_str);
                return;
            };
            std.debug.print(" {s}=\"{s}\"\n", .{ var_name, str });
        }
    }
}

fn executeLoad(ctx: ActionContext, cmd: macro.MacroCommand) void {
    const file_path = cmd.file orelse {
        std.debug.print("    Error: load requires file field\n", .{});
        return;
    };
    const var_name = cmd.as_var orelse {
        std.debug.print("    Error: load requires 'as' field\n", .{});
        return;
    };

    // Read the JSON file
    const dir = std.Io.Dir.cwd();
    var file_buf: [512 * 1024]u8 = undefined;
    const content = dir.readFile(ctx.io, file_path, &file_buf) catch |err| {
        std.debug.print("    Error reading file: {}\n", .{err});
        return;
    };

    // Parse to determine type (array or object)
    var parsed = json.parse(ctx.allocator, content, .{}) catch |err| {
        std.debug.print("    Error parsing JSON: {}\n", .{err});
        return;
    };
    defer parsed.deinit(ctx.allocator);

    // Store in variables
    const key = ctx.allocator.dupe(u8, var_name) catch return;
    const json_copy = ctx.allocator.dupe(u8, content) catch {
        ctx.allocator.free(key);
        return;
    };

    // Remove old value if exists
    if (ctx.variables.fetchRemove(key)) |old| {
        ctx.allocator.free(old.key);
        var old_val = old.value;
        old_val.deinit(ctx.allocator);
    }

    // Determine the type
    const is_array = parsed == .array;
    const is_object = parsed == .object;

    if (!is_array and !is_object) {
        ctx.allocator.free(json_copy);
        ctx.allocator.free(key);
        std.debug.print("    Error: file must contain array or object\n", .{});
        return;
    }

    const var_val: state.VarValue = if (is_array)
        .{ .array = json_copy }
    else
        .{ .object = json_copy };

    ctx.variables.put(key, var_val) catch {
        ctx.allocator.free(key);
        switch (var_val) {
            .array => |a| ctx.allocator.free(a),
            .object => |o| ctx.allocator.free(o),
            .string => |s| ctx.allocator.free(s),
            else => {},
        }
        return;
    };

    const item_count = if (parsed == .array) parsed.array.items.len else 1;
    std.debug.print(" {s} ({} items)\n", .{ var_name, item_count });
}

fn executeForeach(ctx: ActionContext, cmd: macro.MacroCommand) anyerror!void {
    const executor = @import("executor.zig");

    const source_var = cmd.source orelse {
        std.debug.print("    Error: foreach requires source field\n", .{});
        return;
    };
    const loop_var_name = cmd.as_var orelse {
        std.debug.print("    Error: foreach requires 'as' field\n", .{});
        return;
    };
    const target_file = cmd.file orelse {
        std.debug.print("    Error: foreach requires file field\n", .{});
        return;
    };

    // Get the source variable (remove $ prefix if present)
    const var_name = if (source_var.len > 0 and source_var[0] == '$')
        source_var[1..]
    else
        source_var;

    const source_val = ctx.variables.get(var_name) orelse {
        std.debug.print("    Error: variable '{s}' not found\n", .{var_name});
        return;
    };

    // Must be an array
    const array_len = source_val.arrayLen(ctx.allocator) orelse {
        std.debug.print("    Error: '{s}' is not an array\n", .{var_name});
        return;
    };

    std.debug.print(" iterating {} items\n", .{array_len});

    const on_error_continue = if (cmd.on_error) |oe|
        std.mem.eql(u8, oe, "continue")
    else
        true; // default is continue

    const max_iter = cmd.max_iterations orelse @as(u32, @intCast(array_len));
    const actual_count = @min(array_len, max_iter);

    // Initialize report for tracking
    var report = state.ForeachReport{
        .source_var = ctx.allocator.dupe(u8, source_var) catch null,
        .macro_file = ctx.allocator.dupe(u8, ctx.macro_file) catch null,
        .nested_macro = ctx.allocator.dupe(u8, target_file) catch null,
        .started_at = state.getTimestamp(ctx.allocator, ctx.io),
        .total_items = array_len,
    };
    defer report.deinit(ctx.allocator);

    // Iterate over array items
    var idx: usize = 0;
    while (idx < actual_count) : (idx += 1) {
        // Set loop index variables ($_index and $_iteration)
        setLoopIndexVars(ctx, @intCast(idx));

        // Check break conditions before each iteration
        if (cmd.break_if_exists) |sel| {
            if (elementExists(ctx, sel)) {
                std.debug.print("  foreach stopped: break_if_exists matched\n", .{});
                break;
            }
        }
        if (cmd.break_if_not_exists) |sel| {
            if (!elementExists(ctx, sel)) {
                std.debug.print("  foreach stopped: break_if_not_exists matched\n", .{});
                break;
            }
        }

        const item_json = source_val.arrayGet(ctx.allocator, idx) orelse {
            report.addResult(ctx.allocator, .{
                .index = idx,
                .status = .skipped,
                .error_message = ctx.allocator.dupe(u8, "Failed to get item from array") catch null,
            }) catch {};
            continue;
        };
        defer ctx.allocator.free(item_json);

        const item_id = state.extractItemId(ctx.allocator, item_json);
        const start_ns = std.Io.Timestamp.now(ctx.io, .real).nanoseconds;

        const loop_key = ctx.allocator.dupe(u8, loop_var_name) catch {
            report.addResult(ctx.allocator, .{
                .index = idx,
                .item_id = item_id,
                .status = .skipped,
                .error_message = ctx.allocator.dupe(u8, "Memory allocation failed") catch null,
            }) catch {};
            continue;
        };

        if (ctx.variables.fetchRemove(loop_key)) |old| {
            ctx.allocator.free(old.key);
            var old_val = old.value;
            old_val.deinit(ctx.allocator);
        }

        var item_parsed = json.parse(ctx.allocator, item_json, .{}) catch {
            ctx.allocator.free(loop_key);
            report.addResult(ctx.allocator, .{
                .index = idx,
                .item_id = item_id,
                .status = .skipped,
                .error_message = ctx.allocator.dupe(u8, "Failed to parse item JSON") catch null,
            }) catch {};
            continue;
        };
        defer item_parsed.deinit(ctx.allocator);

        const item_copy = ctx.allocator.dupe(u8, item_json) catch {
            ctx.allocator.free(loop_key);
            report.addResult(ctx.allocator, .{
                .index = idx,
                .item_id = item_id,
                .status = .skipped,
                .error_message = ctx.allocator.dupe(u8, "Memory allocation failed") catch null,
            }) catch {};
            continue;
        };

        const loop_val: state.VarValue = if (item_parsed == .object)
            .{ .object = item_copy }
        else if (item_parsed == .array)
            .{ .array = item_copy }
        else
            .{ .string = item_copy };

        ctx.variables.put(loop_key, loop_val) catch {
            ctx.allocator.free(loop_key);
            switch (loop_val) {
                .object => |o| ctx.allocator.free(o),
                .array => |a| ctx.allocator.free(a),
                .string => |s| ctx.allocator.free(s),
                else => {},
            }
            report.addResult(ctx.allocator, .{
                .index = idx,
                .item_id = item_id,
                .status = .skipped,
                .error_message = ctx.allocator.dupe(u8, "Failed to store loop variable") catch null,
            }) catch {};
            continue;
        };

        std.debug.print("  [foreach {}/{}] ", .{ idx + 1, array_len });

        const resolved_path = blk: {
            const current_macro_dir = std.fs.path.dirname(ctx.macro_file);
            if (current_macro_dir) |dir_path| {
                const joined = std.fs.path.join(ctx.allocator, &.{ dir_path, target_file }) catch break :blk target_file;
                const test_dir = std.Io.Dir.cwd();
                var test_buf: [1]u8 = undefined;
                if (test_dir.readFile(ctx.io, joined, &test_buf)) |_| {
                    break :blk joined;
                } else |_| {
                    ctx.allocator.free(joined);
                    break :blk target_file;
                }
            }
            break :blk target_file;
        };
        defer if (resolved_path.ptr != target_file.ptr) ctx.allocator.free(resolved_path);

        var nested_options = ctx.options;
        nested_options.video_orch = ctx.video_orch;
        nested_options.resume_mode = false;
        nested_options.start_index = null;
        nested_options.variables = ctx.variables;
        nested_options.call_stack = ctx.call_stack;

        const end_ns = std.Io.Timestamp.now(ctx.io, .real).nanoseconds;
        const duration_ms: u64 = @intCast(@divTrunc(end_ns - start_ns, 1_000_000));

        executor.replayCommandsWithOptions(ctx.session, ctx.allocator, ctx.io, resolved_path, nested_options) catch |err| {
            switch (err) {
                error.MarkSuccess => {
                    report.addResult(ctx.allocator, .{ .index = idx, .item_id = item_id, .status = .success, .duration_ms = duration_ms }) catch {};
                    continue;
                },
                error.MarkSkipped => {
                    report.addResult(ctx.allocator, .{ .index = idx, .item_id = item_id, .status = .skipped, .duration_ms = duration_ms }) catch {};
                    continue;
                },
                error.MarkFailed => {
                    report.addResult(ctx.allocator, .{ .index = idx, .item_id = item_id, .status = .failed, .error_message = ctx.allocator.dupe(u8, "Marked as failed") catch null, .duration_ms = duration_ms }) catch {};
                    if (!on_error_continue) {
                        std.debug.print("  foreach stopped due to mark failed\n", .{});
                        break;
                    }
                    continue;
                },
                else => {
                    std.debug.print("    Error in foreach iteration {}: {}\n", .{ idx + 1, err });
                    const err_msg = std.fmt.allocPrint(ctx.allocator, "{}", .{err}) catch null;
                    report.addResult(ctx.allocator, .{ .index = idx, .item_id = item_id, .status = .failed, .error_message = err_msg, .duration_ms = duration_ms }) catch {};
                    if (!on_error_continue) {
                        std.debug.print("  foreach stopped due to error\n", .{});
                        break;
                    }
                    continue;
                },
            }
        };

        report.addResult(ctx.allocator, .{ .index = idx, .item_id = item_id, .status = .success, .duration_ms = duration_ms }) catch {};
    }

    // Clean up loop index variables
    cleanupLoopIndexVars(ctx);

    report.completed_at = state.getTimestamp(ctx.allocator, ctx.io);

    const report_path = blk: {
        const base = if (std.mem.endsWith(u8, ctx.macro_file, ".json"))
            ctx.macro_file[0 .. ctx.macro_file.len - 5]
        else
            ctx.macro_file;
        break :blk std.fmt.allocPrint(ctx.allocator, "{s}.report.json", .{base}) catch null;
    };

    if (report_path) |rp| {
        defer ctx.allocator.free(rp);
        state.saveForeachReport(&report, ctx.allocator, ctx.io, rp) catch |err| {
            std.debug.print("  Warning: failed to save report: {}\n", .{err});
        };
        std.debug.print("  foreach complete: {}/{} succeeded, {} failed\n", .{ report.succeeded, report.total_items, report.failed });
        std.debug.print("  Report saved: {s}\n", .{rp});
    } else {
        std.debug.print("  foreach complete: {}/{} succeeded, {} failed\n", .{ report.succeeded, report.total_items, report.failed });
    }
}

fn executeMark(cmd: macro.MacroCommand) anyerror {
    const status_str = cmd.value orelse "success";
    std.debug.print(" {s}\n", .{status_str});

    if (std.mem.eql(u8, status_str, "success")) {
        return error.MarkSuccess;
    } else if (std.mem.eql(u8, status_str, "skipped")) {
        return error.MarkSkipped;
    } else {
        return error.MarkFailed;
    }
}

fn executeIf(ctx: ActionContext, cmd: macro.MacroCommand) anyerror!void {
    const condition_met = evaluateCondition(ctx, cmd);

    std.debug.print(" -> {s}\n", .{if (condition_met) "true" else "false"});

    if (condition_met) {
        if (cmd.then_file) |target| {
            try executeGotoFile(ctx, target);
        }
    } else {
        if (cmd.else_file) |target| {
            try executeGotoFile(ctx, target);
        }
    }
}

fn evaluateCondition(ctx: ActionContext, cmd: macro.MacroCommand) bool {
    // if_exists: check if selector matches any elements
    if (cmd.if_exists) |sel| {
        return elementExists(ctx, sel);
    }

    // if_not_exists: check if selector matches NO elements
    if (cmd.if_not_exists) |sel| {
        return !elementExists(ctx, sel);
    }

    // if_text: check text content of selector (uses contains field)
    if (cmd.if_text) |sel| {
        const text = getElementText(ctx, sel) orelse return false;
        defer ctx.allocator.free(text);

        if (cmd.contains) |pattern| {
            return std.mem.indexOf(u8, text, pattern) != null;
        }
        if (cmd.text_eq) |expected| {
            return std.mem.eql(u8, text, expected);
        }
        // If no comparison specified, just check if text is non-empty
        return text.len > 0;
    }

    // if_url: check current URL against pattern (supports * wildcard)
    if (cmd.if_url) |pattern| {
        const current_url = getCurrentUrl(ctx) orelse return false;
        defer ctx.allocator.free(current_url);
        return utils.matchesGlobPattern(current_url, pattern);
    }

    // if_var: check variable value
    if (cmd.if_var) |var_ref| {
        const var_name = if (var_ref.len > 0 and var_ref[0] == '$')
            var_ref[1..]
        else
            var_ref;

        const var_val = ctx.variables.get(var_name) orelse return false;

        // Check comparison fields
        if (cmd.count_gt) |threshold| {
            const val_int = var_val.asInt() orelse return false;
            const thresh_int = parseIntOrVar(ctx, threshold) orelse return false;
            return val_int > thresh_int;
        }
        if (cmd.count_lt) |threshold| {
            const val_int = var_val.asInt() orelse return false;
            const thresh_int = parseIntOrVar(ctx, threshold) orelse return false;
            return val_int < thresh_int;
        }
        if (cmd.count_gte) |threshold| {
            const val_int = var_val.asInt() orelse return false;
            const thresh_int = parseIntOrVar(ctx, threshold) orelse return false;
            return val_int >= thresh_int;
        }
        if (cmd.count_lte) |threshold| {
            const val_int = var_val.asInt() orelse return false;
            const thresh_int = parseIntOrVar(ctx, threshold) orelse return false;
            return val_int <= thresh_int;
        }
        if (cmd.text_eq) |expected| {
            const val_str = var_val.asString() orelse return false;
            return std.mem.eql(u8, val_str, expected);
        }
        if (cmd.text_neq) |expected| {
            const val_str = var_val.asString() orelse return false;
            return !std.mem.eql(u8, val_str, expected);
        }

        // Default: check if variable exists and is truthy
        return switch (var_val) {
            .int => |i| i != 0,
            .string => |s| s.len > 0,
            .array, .object => true,
        };
    }

    return false;
}

fn elementExists(ctx: ActionContext, selector: []const u8) bool {
    const escaped_sel = utils.escapeForJs(ctx.allocator, selector) catch return false;
    defer ctx.allocator.free(escaped_sel);

    const js = std.fmt.allocPrint(ctx.allocator, "document.querySelector('{s}') !== null", .{escaped_sel}) catch return false;
    defer ctx.allocator.free(js);

    var runtime = cdp.Runtime.init(ctx.session);
    var result = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch return false;
    defer result.deinit(ctx.allocator);

    return result.asBool() orelse false;
}

fn getElementText(ctx: ActionContext, selector: []const u8) ?[]const u8 {
    const escaped_sel = utils.escapeForJs(ctx.allocator, selector) catch return null;
    defer ctx.allocator.free(escaped_sel);

    const js = std.fmt.allocPrint(ctx.allocator, "document.querySelector('{s}')?.textContent?.trim()||''", .{escaped_sel}) catch return null;
    defer ctx.allocator.free(js);

    var runtime = cdp.Runtime.init(ctx.session);
    var result = runtime.evaluate(ctx.allocator, js, .{ .return_by_value = true }) catch return null;
    defer result.deinit(ctx.allocator);

    if (result.asString()) |str| {
        return ctx.allocator.dupe(u8, str) catch null;
    }
    return null;
}

fn getCurrentUrl(ctx: ActionContext) ?[]const u8 {
    var runtime = cdp.Runtime.init(ctx.session);
    var result = runtime.evaluate(ctx.allocator, "window.location.href", .{ .return_by_value = true }) catch return null;
    defer result.deinit(ctx.allocator);

    if (result.asString()) |str| {
        return ctx.allocator.dupe(u8, str) catch null;
    }
    return null;
}

fn parseIntOrVar(ctx: ActionContext, value: []const u8) ?i64 {
    // If starts with $, look up variable
    if (value.len > 0 and value[0] == '$') {
        const var_name = value[1..];
        const var_val = ctx.variables.get(var_name) orelse return null;
        return var_val.asInt();
    }
    // Otherwise parse as integer
    return std.fmt.parseInt(i64, value, 10) catch null;
}

fn executeGotoFile(ctx: ActionContext, target_file: []const u8) anyerror!void {
    const executor = @import("executor.zig");

    // Resolve target file path relative to macro file's directory
    const resolved_path = blk: {
        const macro_dir = std.fs.path.dirname(ctx.macro_file);
        if (macro_dir) |dir| {
            const joined = std.fs.path.join(ctx.allocator, &.{ dir, target_file }) catch break :blk target_file;
            const test_dir = std.Io.Dir.cwd();
            var test_buf: [1]u8 = undefined;
            if (test_dir.readFile(ctx.io, joined, &test_buf)) |_| {
                break :blk joined;
            } else |_| {
                ctx.allocator.free(joined);
                break :blk target_file;
            }
        }
        break :blk target_file;
    };
    defer if (resolved_path.ptr != target_file.ptr) ctx.allocator.free(resolved_path);

    // Check for circular include
    for (ctx.call_stack.items) |stack_file| {
        if (std.mem.eql(u8, stack_file, resolved_path)) {
            std.debug.print("    Error: circular include detected: {s}\n", .{resolved_path});
            std.debug.print("    Call stack: ", .{});
            for (ctx.call_stack.items, 0..) |sf, i| {
                if (i > 0) std.debug.print(" -> ", .{});
                std.debug.print("{s}", .{sf});
            }
            std.debug.print(" -> {s}\n", .{resolved_path});
            return error.CircularInclude;
        }
    }

    std.debug.print("    -> {s}\n", .{resolved_path});

    var nested_options = ctx.options;
    nested_options.video_orch = ctx.video_orch;
    nested_options.resume_mode = false;
    nested_options.start_index = null;
    nested_options.variables = ctx.variables;
    nested_options.call_stack = ctx.call_stack;

    executor.replayCommandsWithOptions(ctx.session, ctx.allocator, ctx.io, resolved_path, nested_options) catch |err| {
        switch (err) {
            error.MarkSuccess, error.MarkFailed, error.MarkSkipped => return err,
            else => {
                std.debug.print("    Error replaying {s}: {}\n", .{ resolved_path, err });
                return err;
            },
        }
    };
}

fn executeRepeat(ctx: ActionContext, cmd: macro.MacroCommand) anyerror!void {
    const target_file = cmd.file orelse {
        std.debug.print("    Error: repeat requires file field\n", .{});
        return;
    };

    // Get iteration count from repeat_count or repeat_count_var
    const count: u32 = blk: {
        if (cmd.repeat_count) |c| break :blk c;
        if (cmd.repeat_count_var) |var_ref| {
            const var_name = if (var_ref.len > 0 and var_ref[0] == '$')
                var_ref[1..]
            else
                var_ref;
            const var_val = ctx.variables.get(var_name) orelse {
                std.debug.print("    Error: variable '{s}' not found\n", .{var_name});
                return;
            };
            const int_val = var_val.asInt() orelse {
                std.debug.print("    Error: variable '{s}' is not an integer\n", .{var_name});
                return;
            };
            if (int_val < 0) {
                std.debug.print("    Error: repeat count cannot be negative\n", .{});
                return;
            }
            break :blk @intCast(int_val);
        }
        std.debug.print("    Error: repeat requires repeat_count or repeat_count_var\n", .{});
        return;
    };

    std.debug.print(" {} iterations\n", .{count});

    const max_iter = cmd.max_iterations orelse count;
    const actual_count = @min(count, max_iter);

    var idx: u32 = 0;
    while (idx < actual_count) : (idx += 1) {
        // Set loop index variables
        setLoopIndexVars(ctx, idx);

        std.debug.print("  [repeat {}/{}]\n", .{ idx + 1, count });

        // Check break conditions
        if (cmd.break_if_exists) |sel| {
            if (elementExists(ctx, sel)) {
                std.debug.print("  repeat stopped: break_if_exists matched\n", .{});
                break;
            }
        }
        if (cmd.break_if_not_exists) |sel| {
            if (!elementExists(ctx, sel)) {
                std.debug.print("  repeat stopped: break_if_not_exists matched\n", .{});
                break;
            }
        }

        executeGotoFile(ctx, target_file) catch |err| {
            switch (err) {
                error.MarkSuccess => continue,
                error.MarkSkipped => continue,
                error.MarkFailed => {
                    std.debug.print("  repeat stopped due to mark failed\n", .{});
                    break;
                },
                else => {
                    std.debug.print("    Error in repeat iteration {}: {}\n", .{ idx + 1, err });
                    break;
                },
            }
        };
    }

    // Clean up loop index variables
    cleanupLoopIndexVars(ctx);
    std.debug.print("  repeat complete: {} iterations\n", .{idx});
}

fn setLoopIndexVars(ctx: ActionContext, idx: u32) void {
    // Set $_index (0-based) and $_iteration (1-based)
    const index_key = ctx.allocator.dupe(u8, "_index") catch return;
    const iter_key = ctx.allocator.dupe(u8, "_iteration") catch {
        ctx.allocator.free(index_key);
        return;
    };

    // Remove old values if exist
    if (ctx.variables.fetchRemove(index_key)) |old| {
        ctx.allocator.free(old.key);
        var old_val = old.value;
        old_val.deinit(ctx.allocator);
    }
    if (ctx.variables.fetchRemove(iter_key)) |old| {
        ctx.allocator.free(old.key);
        var old_val = old.value;
        old_val.deinit(ctx.allocator);
    }

    ctx.variables.put(index_key, .{ .int = @intCast(idx) }) catch {
        ctx.allocator.free(index_key);
        ctx.allocator.free(iter_key);
        return;
    };
    ctx.variables.put(iter_key, .{ .int = @intCast(idx + 1) }) catch {
        ctx.allocator.free(iter_key);
        return;
    };
}

fn cleanupLoopIndexVars(ctx: ActionContext) void {
    if (ctx.variables.fetchRemove("_index")) |old| {
        ctx.allocator.free(old.key);
        var old_val = old.value;
        old_val.deinit(ctx.allocator);
    }
    if (ctx.variables.fetchRemove("_iteration")) |old| {
        ctx.allocator.free(old.key);
        var old_val = old.value;
        old_val.deinit(ctx.allocator);
    }
}
