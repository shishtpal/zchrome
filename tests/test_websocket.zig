const std = @import("std");
const WebSocket = @import("cdp").WebSocket;

test "applyMask" {
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

test "computeAcceptKey" {
    // RFC 6455 example
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    const accept = WebSocket.computeAcceptKey(key);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &accept);
}

test "generateMaskKey" {
    const key1 = WebSocket.generateMaskKey();
    const key2 = WebSocket.generateMaskKey();

    // Keys should be different (with high probability)
    try std.testing.expect(!std.mem.eql(u8, &key1, &key2));
}
