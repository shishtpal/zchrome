# Base64 Utilities

Functions for encoding and decoding Base64 data, commonly used for screenshots and PDFs.

## Import

```zig
const cdp = @import("cdp");
const base64 = cdp.base64;
```

## Functions

### decodeAlloc

Decode a Base64 string to bytes.

```zig
pub fn decodeAlloc(allocator: Allocator, input: []const u8) ![]u8
```

**Example:**

```zig
// Screenshot returns Base64-encoded data
const screenshot_b64 = try page.captureScreenshot(allocator, .{ .format = .png });
defer allocator.free(screenshot_b64);

// Decode to raw bytes
const screenshot_bytes = try base64.decodeAlloc(allocator, screenshot_b64);
defer allocator.free(screenshot_bytes);

std.debug.print("Decoded {} bytes\n", .{screenshot_bytes.len});
```

### encodeAlloc

Encode bytes to a Base64 string.

```zig
pub fn encodeAlloc(allocator: Allocator, input: []const u8) ![]u8
```

**Example:**

```zig
// Encode data for request body
const json_data = "{\"key\": \"value\"}";
const encoded = try base64.encodeAlloc(allocator, json_data);
defer allocator.free(encoded);

// Use in fulfillRequest
try fetch.fulfillRequest(request_id, 200, .{
    .body = encoded,
});
```

### calcDecodedSize

Calculate the size of decoded data without decoding.

```zig
pub fn calcDecodedSize(input: []const u8) usize
```

**Example:**

```zig
const size = base64.calcDecodedSize(screenshot_b64);
std.debug.print("Will decode to {} bytes\n", .{size});
```

## Common Use Cases

### Save Screenshot to Memory

```zig
const screenshot_b64 = try page.captureScreenshot(allocator, .{ .format = .png });
defer allocator.free(screenshot_b64);

const png_data = try base64.decodeAlloc(allocator, screenshot_b64);
defer allocator.free(png_data);

// png_data now contains raw PNG bytes
```

### Save PDF to Memory

```zig
const pdf_b64 = try page.printToPDF(allocator, .{});
defer allocator.free(pdf_b64);

const pdf_data = try base64.decodeAlloc(allocator, pdf_b64);
defer allocator.free(pdf_data);

// pdf_data now contains raw PDF bytes
```

### Encode Response Body

```zig
const response_json = "{\"status\": \"ok\"}";
const encoded_body = try base64.encodeAlloc(allocator, response_json);
defer allocator.free(encoded_body);

try fetch.fulfillRequest(request_id, 200, .{
    .response_headers = &[_]Header{
        .{ .name = "Content-Type", .value = "application/json" },
    },
    .body = encoded_body,
});
```

## Error Handling

```zig
const decoded = base64.decodeAlloc(allocator, invalid_input) catch |err| {
    std.debug.print("Invalid Base64: {}\n", .{err});
    return;
};
```
