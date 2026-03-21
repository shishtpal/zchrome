//! Variable interpolation for macro replay.
//!
//! Supports variable references like `$user` and field access like `$user.name`.

const std = @import("std");
const state = @import("../state.zig");

pub const VarValue = state.VarValue;

/// Interpolate variables in a string (e.g., "$user.name" -> "John")
/// Returns a new allocated string if any substitution was made, otherwise returns null
pub fn interpolateVariables(allocator: std.mem.Allocator, input: []const u8, variables: *const std.StringHashMap(VarValue)) ?[]const u8 {
    // Quick check: if no $ in string, no interpolation needed
    if (std.mem.indexOf(u8, input, "$") == null) {
        return null;
    }

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    var made_substitution = false;

    while (i < input.len) {
        if (input[i] == '$' and i + 1 < input.len) {
            // Found a potential variable reference
            const var_start = i + 1;
            var var_end = var_start;

            // Scan variable name (alphanumeric, underscore, dots for field access)
            while (var_end < input.len and (std.ascii.isAlphanumeric(input[var_end]) or input[var_end] == '_' or input[var_end] == '.' or input[var_end] == '-')) {
                var_end += 1;
            }

            if (var_end > var_start) {
                const var_ref = input[var_start..var_end];

                // Check if it's a field access (e.g., "user.name")
                if (std.mem.indexOf(u8, var_ref, ".")) |dot_pos| {
                    const var_name = var_ref[0..dot_pos];
                    const field_path = var_ref[dot_pos + 1 ..];

                    if (variables.get(var_name)) |var_val| {
                        if (var_val.getField(allocator, field_path)) |field_val| {
                            result.appendSlice(allocator, field_val) catch return null;
                            allocator.free(field_val);
                            made_substitution = true;
                            i = var_end;
                            continue;
                        }
                    }
                } else {
                    // Simple variable reference
                    if (variables.get(var_ref)) |var_val| {
                        const val_str: ?[]const u8 = switch (var_val) {
                            .string => |s| s,
                            .int => |int_val| std.fmt.allocPrint(allocator, "{}", .{int_val}) catch null,
                            .array, .object => null, // Can't interpolate complex types directly
                        };
                        if (val_str) |v| {
                            result.appendSlice(allocator, v) catch return null;
                            // Free if we allocated (for int case)
                            if (var_val != .string) allocator.free(v);
                            made_substitution = true;
                            i = var_end;
                            continue;
                        }
                    }
                }
            }
        }

        // No substitution, copy character as-is
        result.append(allocator, input[i]) catch return null;
        i += 1;
    }

    if (!made_substitution) {
        result.deinit(allocator);
        return null;
    }

    return result.toOwnedSlice(allocator) catch null;
}
