const std = @import("std");

const Encoder = std.base64.standard.Encoder;
const Decoder = std.base64.standard.Decoder;

/// Decode a base64 string and return an allocated buffer
pub fn decodeAlloc(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const decoded_len = Decoder.calcSizeForSlice(encoded) catch return error.InvalidBase64;
    const buffer = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(buffer);

    Decoder.decode(buffer, encoded) catch {
        allocator.free(buffer);
        return error.InvalidBase64;
    };

    return buffer;
}

/// Encode data to base64 and return an allocated string
pub fn encodeAlloc(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const encoded_len = Encoder.calcSize(data.len);
    const buffer = try allocator.alloc(u8, encoded_len);
    errdefer allocator.free(buffer);

    _ = Encoder.encode(buffer, data);
    return buffer;
}

/// Calculate the decoded length without allocating
pub fn decodedLength(encoded: []const u8) ?usize {
    return Decoder.calcSizeForSlice(encoded) catch null;
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "encodeAlloc" {
    const result = try encodeAlloc(std.testing.allocator, "Hello, World!");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ==", result);
}

test "decodeAlloc" {
    const result = try decodeAlloc(std.testing.allocator, "SGVsbG8sIFdvcmxkIQ==");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "encode and decode roundtrip" {
    const original = "The quick brown fox jumps over the lazy dog";

    const encoded = try encodeAlloc(std.testing.allocator, original);
    defer std.testing.allocator.free(encoded);

    const decoded = try decodeAlloc(std.testing.allocator, encoded);
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings(original, decoded);
}

test "decodedLength" {
    const len = decodedLength("SGVsbG8=");
    try std.testing.expectEqual(@as(?usize, 5), len);
}

test "decodeAlloc invalid base64" {
    const result = decodeAlloc(std.testing.allocator, "not valid base64!!!");
    try std.testing.expectError(error.InvalidBase64, result);
}
