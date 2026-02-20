const std = @import("std");

// WebSocket opcodes
pub const OPCODE_CONTINUATION: u4 = 0x0;
pub const OPCODE_TEXT: u4 = 0x1;
pub const OPCODE_BINARY: u4 = 0x2;
pub const OPCODE_CLOSE: u4 = 0x8;
pub const OPCODE_PING: u4 = 0x9;
pub const OPCODE_PONG: u4 = 0xA;

test "WebSocket opcodes" {
    try std.testing.expectEqual(@as(u4, 0x0), OPCODE_CONTINUATION);
    try std.testing.expectEqual(@as(u4, 0x1), OPCODE_TEXT);
    try std.testing.expectEqual(@as(u4, 0x2), OPCODE_BINARY);
    try std.testing.expectEqual(@as(u4, 0x8), OPCODE_CLOSE);
    try std.testing.expectEqual(@as(u4, 0x9), OPCODE_PING);
    try std.testing.expectEqual(@as(u4, 0xA), OPCODE_PONG);
}

test "WebSocket masking - XOR roundtrip" {
    var data = [_]u8{ 'H', 'e', 'l', 'l', 'o' };
    const mask = [4]u8{ 0x37, 0xfa, 0x21, 0x3d };

    // Apply mask
    for (&data, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }

    // Verify XOR applied
    try std.testing.expectEqual(@as(u8, 'H' ^ 0x37), data[0]);
    try std.testing.expectEqual(@as(u8, 'e' ^ 0xfa), data[1]);

    // Apply again to unmask
    for (&data, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }
    try std.testing.expectEqualStrings("Hello", &data);
}

test "WebSocket masking - with different data lengths" {
    // Test with length not divisible by 4
    var data1 = [_]u8{ 'a', 'b', 'c' };
    const mask = [4]u8{ 0x01, 0x02, 0x03, 0x04 };

    for (&data1, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }
    for (&data1, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }
    try std.testing.expectEqualStrings("abc", &data1);

    // Test with length divisible by 4
    var data2 = [_]u8{ 'a', 'b', 'c', 'd' };
    for (&data2, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }
    for (&data2, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }
    try std.testing.expectEqualStrings("abcd", &data2);
}

test "WebSocket frame structure" {
    // Basic frame structure validation
    // FIN bit (1) + RSV1-3 (0) + Opcode (4 bits) = 1 byte
    const fin: u8 = 0x80; // FIN bit set
    const opcode_text: u8 = 0x01; // Text frame

    const first_byte = fin | opcode_text;
    try std.testing.expectEqual(@as(u8, 0x81), first_byte);
}

test "WebSocket payload length encoding" {
    // Small payload (0-125): length is in second byte
    const small_payload: usize = 100;
    try std.testing.expect(small_payload <= 125);

    // Medium payload (126-65535): 126 in second byte, 2 bytes follow
    const medium_payload: usize = 1000;
    try std.testing.expect(medium_payload > 125 and medium_payload <= 65535);

    // Large payload (>65535): 127 in second byte, 8 bytes follow
    const large_payload: usize = 100000;
    try std.testing.expect(large_payload > 65535);
}
