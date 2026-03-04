const std = @import("std");

const dialog_cmd = @import("../cli/commands/dialog.zig");

test "dialog parse - no args" {
    const parsed = try dialog_cmd.parseDialogArgs(std.testing.allocator, &.{});
    try std.testing.expect(parsed == null);
}

test "dialog parse - accept without text" {
    const parsed = try dialog_cmd.parseDialogArgs(std.testing.allocator, &.{"accept"});
    try std.testing.expect(parsed != null);
    defer dialog_cmd.deinitDialogAction(std.testing.allocator, parsed.?);

    switch (parsed.?) {
        .accept => |text| try std.testing.expect(text == null),
        else => try std.testing.expect(false),
    }
}

test "dialog parse - accept with one token" {
    const parsed = try dialog_cmd.parseDialogArgs(std.testing.allocator, &.{ "accept", "hello" });
    try std.testing.expect(parsed != null);
    defer dialog_cmd.deinitDialogAction(std.testing.allocator, parsed.?);

    switch (parsed.?) {
        .accept => |text| {
            try std.testing.expect(text != null);
            try std.testing.expectEqualStrings("hello", text.?);
        },
        else => try std.testing.expect(false),
    }
}

test "dialog parse - accept with multiple tokens" {
    const parsed = try dialog_cmd.parseDialogArgs(std.testing.allocator, &.{ "accept", "hello", "world" });
    try std.testing.expect(parsed != null);
    defer dialog_cmd.deinitDialogAction(std.testing.allocator, parsed.?);

    switch (parsed.?) {
        .accept => |text| {
            try std.testing.expect(text != null);
            try std.testing.expectEqualStrings("hello world", text.?);
        },
        else => try std.testing.expect(false),
    }
}

test "dialog parse - dismiss" {
    const parsed = try dialog_cmd.parseDialogArgs(std.testing.allocator, &.{"dismiss"});
    try std.testing.expect(parsed != null);
    defer dialog_cmd.deinitDialogAction(std.testing.allocator, parsed.?);

    switch (parsed.?) {
        .dismiss => {},
        else => try std.testing.expect(false),
    }
}

test "dialog parse - dismiss ignores extra tokens" {
    const parsed = try dialog_cmd.parseDialogArgs(std.testing.allocator, &.{ "dismiss", "extra" });
    try std.testing.expect(parsed != null);
    defer dialog_cmd.deinitDialogAction(std.testing.allocator, parsed.?);

    switch (parsed.?) {
        .dismiss => {},
        else => try std.testing.expect(false),
    }
}

test "dialog parse - invalid subcommand" {
    const parsed = try dialog_cmd.parseDialogArgs(std.testing.allocator, &.{"invalid"});
    try std.testing.expect(parsed == null);
}
