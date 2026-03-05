//! PNG processing helpers for image diffing.
//!
//! Provides PNG decoding with filter reconstruction and basic encoding.
//! Uses zlib-png for chunk parsing.

const std = @import("std");
const png = @import("png");
const Allocator = std.mem.Allocator;

pub const PngImage = struct {
    width: u32,
    height: u32,
    bit_depth: u8,
    color_type: u8,
    pixels: []u8, // RGBA pixel data
    allocator: Allocator,

    pub fn deinit(self: *PngImage) void {
        self.allocator.free(self.pixels);
    }

    /// Get bytes per pixel based on color type
    pub fn bytesPerPixel(self: PngImage) usize {
        return switch (self.color_type) {
            0 => 1, // Grayscale
            2 => 3, // RGB
            3 => 1, // Indexed
            4 => 2, // Grayscale + Alpha
            6 => 4, // RGBA
            else => 4,
        };
    }
};

pub const PngError = error{
    InvalidPng,
    InvalidIHDR,
    DecompressionFailed,
    InvalidFilterType,
    UnsupportedColorType,
    DimensionMismatch,
    OutOfMemory,
};

/// Decode a PNG file to RGBA pixel buffer
pub fn decodePng(allocator: Allocator, data: []u8) !PngImage {
    // Initialize PNG decoder
    var decoder = png.Decoder.init(allocator, data) catch |err| {
        std.debug.print("PNG decoder init failed: {}\n", .{err});
        return PngError.InvalidPng;
    };
    defer decoder.free();

    // Read IHDR chunk (first chunk after signature)
    decoder.nextChunk() catch |err| {
        std.debug.print("Failed to read first chunk: {}\n", .{err});
        return PngError.InvalidPng;
    };
    const ihdr = png.chunks.IHDR.read(decoder.curr_chunk.?) catch |err| {
        std.debug.print("Failed to parse IHDR: {}\n", .{err});
        return PngError.InvalidIHDR;
    };

    // Collect IDAT chunk data
    var compressed_data: std.ArrayListUnmanaged(u8) = .{};
    defer compressed_data.deinit(allocator);

    var chunk_count: usize = 0;
    while (!decoder.isLastChunk()) {
        decoder.nextChunk() catch break;
        if (decoder.curr_chunk) |chunk| {
            if (png.chunks.IDAT.isIDATChunk(chunk)) {
                try compressed_data.appendSlice(allocator, chunk.data);
                chunk_count += 1;
            }
        }
    }

    if (compressed_data.items.len == 0) {
        std.debug.print("No IDAT chunks found\n", .{});
        return PngError.InvalidPng;
    }

    // Calculate expected size
    const bpp = bytesPerPixelForColorType(ihdr.color_type);
    const scanline_len = ihdr.width * bpp + 1; // +1 for filter byte
    const expected_size = scanline_len * ihdr.height;

    // Decompress using flate with zlib container (handles header/footer)
    if (compressed_data.items.len < 6) { // 2-byte header + minimum data + 4-byte footer
        std.debug.print("Compressed data too small: {} bytes\n", .{compressed_data.items.len});
        return PngError.DecompressionFailed;
    }

    var input_reader = std.Io.Reader.fixed(compressed_data.items);

    var window_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decomp = std.compress.flate.Decompress.init(&input_reader, .zlib, &window_buf);

    // Pre-allocate output buffer
    const raw_data = try allocator.alloc(u8, expected_size);
    defer allocator.free(raw_data);

    // Read decompressed data using take()
    var total_read: usize = 0;
    while (total_read < expected_size) {
        const remaining = expected_size - total_read;
        const chunk_size = @min(remaining, 4096);

        const bytes = decomp.reader.take(chunk_size) catch |err| {
            // EndOfStream is expected when we've read all data
            if (total_read > 0) break;
            std.debug.print("Decompression error at offset {}: {}\n", .{ total_read, err });
            return PngError.DecompressionFailed;
        };

        if (bytes.len == 0) break;

        @memcpy(raw_data[total_read..][0..bytes.len], bytes);
        total_read += bytes.len;
    }

    if (total_read < expected_size) {
        std.debug.print("Decompressed {} bytes, expected {} bytes\n", .{ total_read, expected_size });
        return PngError.DecompressionFailed;
    }

    // Apply PNG filters and convert to RGBA
    const pixels = try applyFilters(allocator, raw_data, ihdr.width, ihdr.height, ihdr.color_type);

    return PngImage{
        .width = ihdr.width,
        .height = ihdr.height,
        .bit_depth = ihdr.bit_depth,
        .color_type = ihdr.color_type,
        .pixels = pixels,
        .allocator = allocator,
    };
}

fn bytesPerPixelForColorType(color_type: u8) usize {
    return switch (color_type) {
        0 => 1, // Grayscale
        2 => 3, // RGB
        3 => 1, // Indexed
        4 => 2, // Grayscale + Alpha
        6 => 4, // RGBA
        else => 4,
    };
}

/// Apply PNG filters to reconstruct pixel data
fn applyFilters(
    allocator: Allocator,
    raw: []const u8,
    width: u32,
    height: u32,
    color_type: u8,
) ![]u8 {
    const bpp = bytesPerPixelForColorType(color_type);
    const scanline_len = width * bpp;
    const raw_scanline_len = scanline_len + 1; // +1 for filter byte

    // Allocate RGBA output buffer
    const output_size = width * height * 4;
    const output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    // Previous scanline (for Up/Average/Paeth filters)
    var prev_scanline: []u8 = try allocator.alloc(u8, scanline_len);
    defer allocator.free(prev_scanline);
    @memset(prev_scanline, 0);

    // Current scanline buffer
    var curr_scanline: []u8 = try allocator.alloc(u8, scanline_len);
    defer allocator.free(curr_scanline);

    for (0..height) |y| {
        const raw_offset = y * raw_scanline_len;
        if (raw_offset >= raw.len) break;

        const filter_type = raw[raw_offset];
        const scanline_data = raw[raw_offset + 1 ..][0..scanline_len];

        // Apply filter
        try unfilterScanline(curr_scanline, scanline_data, prev_scanline, filter_type, bpp);

        // Convert to RGBA and write to output
        const out_offset = y * width * 4;
        for (0..width) |x| {
            const src_offset = x * bpp;
            const dst_offset = out_offset + x * 4;

            switch (color_type) {
                0 => { // Grayscale
                    const gray = curr_scanline[src_offset];
                    output[dst_offset] = gray;
                    output[dst_offset + 1] = gray;
                    output[dst_offset + 2] = gray;
                    output[dst_offset + 3] = 255;
                },
                2 => { // RGB
                    output[dst_offset] = curr_scanline[src_offset];
                    output[dst_offset + 1] = curr_scanline[src_offset + 1];
                    output[dst_offset + 2] = curr_scanline[src_offset + 2];
                    output[dst_offset + 3] = 255;
                },
                4 => { // Grayscale + Alpha
                    const gray = curr_scanline[src_offset];
                    output[dst_offset] = gray;
                    output[dst_offset + 1] = gray;
                    output[dst_offset + 2] = gray;
                    output[dst_offset + 3] = curr_scanline[src_offset + 1];
                },
                6 => { // RGBA
                    output[dst_offset] = curr_scanline[src_offset];
                    output[dst_offset + 1] = curr_scanline[src_offset + 1];
                    output[dst_offset + 2] = curr_scanline[src_offset + 2];
                    output[dst_offset + 3] = curr_scanline[src_offset + 3];
                },
                else => {
                    // Default: copy as grayscale
                    const gray = curr_scanline[src_offset];
                    output[dst_offset] = gray;
                    output[dst_offset + 1] = gray;
                    output[dst_offset + 2] = gray;
                    output[dst_offset + 3] = 255;
                },
            }
        }

        // Swap scanlines
        const tmp = prev_scanline;
        prev_scanline = curr_scanline;
        curr_scanline = tmp;
    }

    return output;
}

/// Unfilter a single scanline
fn unfilterScanline(
    dest: []u8,
    src: []const u8,
    prev: []const u8,
    filter_type: u8,
    bpp: usize,
) !void {
    switch (filter_type) {
        0 => { // None
            @memcpy(dest, src);
        },
        1 => { // Sub
            for (0..dest.len) |i| {
                const a: u8 = if (i >= bpp) dest[i - bpp] else 0;
                dest[i] = src[i] +% a;
            }
        },
        2 => { // Up
            for (0..dest.len) |i| {
                const b = prev[i];
                dest[i] = src[i] +% b;
            }
        },
        3 => { // Average
            for (0..dest.len) |i| {
                const a: u16 = if (i >= bpp) dest[i - bpp] else 0;
                const b: u16 = prev[i];
                const avg: u8 = @intCast((a + b) / 2);
                dest[i] = src[i] +% avg;
            }
        },
        4 => { // Paeth
            for (0..dest.len) |i| {
                const a: i32 = if (i >= bpp) dest[i - bpp] else 0;
                const b: i32 = prev[i];
                const c: i32 = if (i >= bpp) prev[i - bpp] else 0;
                dest[i] = src[i] +% paethPredictor(a, b, c);
            }
        },
        else => return PngError.InvalidFilterType,
    }
}

/// Paeth predictor function
fn paethPredictor(a: i32, b: i32, c: i32) u8 {
    const p = a + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);

    if (pa <= pb and pa <= pc) {
        return @intCast(a);
    } else if (pb <= pc) {
        return @intCast(b);
    } else {
        return @intCast(c);
    }
}

/// Encode RGBA pixels to PNG format (simple implementation)
pub fn encodePng(allocator: Allocator, pixels: []const u8, width: u32, height: u32) ![]u8 {
    var output: std.ArrayListUnmanaged(u8) = .{};
    errdefer output.deinit(allocator);

    // PNG signature
    try output.appendSlice(allocator, &[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });

    // IHDR chunk
    var ihdr_data: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr_data[0..4], width, .big);
    std.mem.writeInt(u32, ihdr_data[4..8], height, .big);
    ihdr_data[8] = 8; // bit depth
    ihdr_data[9] = 6; // color type (RGBA)
    ihdr_data[10] = 0; // compression
    ihdr_data[11] = 0; // filter
    ihdr_data[12] = 0; // interlace
    try writeChunk(allocator, &output, "IHDR", &ihdr_data);

    // IDAT chunk - prepare filtered scanlines
    var filtered: std.ArrayListUnmanaged(u8) = .{};
    defer filtered.deinit(allocator);

    const scanline_len = width * 4;
    for (0..height) |y| {
        try filtered.append(allocator, 0); // Filter type: None
        const offset = y * scanline_len;
        try filtered.appendSlice(allocator, pixels[offset..][0..scanline_len]);
    }

    // Compress with zlib/deflate
    var compressed: std.ArrayListUnmanaged(u8) = .{};
    defer compressed.deinit(allocator);

    // zlib header
    try compressed.append(allocator, 0x78); // CMF
    try compressed.append(allocator, 0x9C); // FLG

    // Deflate compress (using stored blocks for simplicity)
    var remaining = filtered.items;
    while (remaining.len > 0) {
        const block_size = @min(remaining.len, 65535);
        const is_final: u8 = if (remaining.len <= 65535) 1 else 0;

        try compressed.append(allocator, is_final); // BFINAL + BTYPE (stored)
        try compressed.appendSlice(allocator, &std.mem.toBytes(@as(u16, @intCast(block_size))));
        try compressed.appendSlice(allocator, &std.mem.toBytes(~@as(u16, @intCast(block_size))));
        try compressed.appendSlice(allocator, remaining[0..block_size]);

        remaining = remaining[block_size..];
    }

    // Adler-32 checksum
    const adler = adler32(filtered.items);
    try compressed.appendSlice(allocator, &std.mem.toBytes(std.mem.nativeToBig(u32, adler)));

    try writeChunk(allocator, &output, "IDAT", compressed.items);

    // IEND chunk
    try writeChunk(allocator, &output, "IEND", &[_]u8{});

    return output.toOwnedSlice(allocator);
}

fn writeChunk(allocator: Allocator, output: *std.ArrayListUnmanaged(u8), chunk_type: []const u8, data: []const u8) !void {
    // Length (big-endian)
    const len_bytes = std.mem.toBytes(std.mem.nativeToBig(u32, @intCast(data.len)));
    try output.appendSlice(allocator, &len_bytes);

    // Type
    try output.appendSlice(allocator, chunk_type);

    // Data
    try output.appendSlice(allocator, data);

    // CRC32
    var crc_data: std.ArrayListUnmanaged(u8) = .{};
    defer crc_data.deinit(allocator);
    try crc_data.appendSlice(allocator, chunk_type);
    try crc_data.appendSlice(allocator, data);

    const crc = crc32(crc_data.items);
    const crc_bytes = std.mem.toBytes(std.mem.nativeToBig(u32, crc));
    try output.appendSlice(allocator, &crc_bytes);
}

/// CRC32 for PNG chunks
fn crc32(data: []const u8) u32 {
    const table = comptime blk: {
        @setEvalBranchQuota(10000);
        var t: [256]u32 = undefined;
        for (0..256) |n| {
            var c: u32 = @intCast(n);
            for (0..8) |_| {
                if (c & 1 != 0) {
                    c = 0xedb88320 ^ (c >> 1);
                } else {
                    c = c >> 1;
                }
            }
            t[n] = c;
        }
        break :blk t;
    };

    var crc: u32 = 0xffffffff;
    for (data) |byte| {
        crc = table[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return crc ^ 0xffffffff;
}

/// Adler-32 checksum for zlib
fn adler32(data: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;

    for (data) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }

    return (b << 16) | a;
}
