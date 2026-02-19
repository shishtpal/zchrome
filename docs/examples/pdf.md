# PDF Generation

Generate PDF documents from web pages.

## Basic PDF

```zig
const std = @import("std");
const cdp = @import("cdp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var browser = try cdp.Browser.launch(.{
        .headless = .new,
        .allocator = allocator,
        .io = init.io,
    });
    defer browser.close();

    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, "https://example.com");

    // Wait for load
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    // Generate PDF
    const pdf_data = try page.printToPDF(allocator, .{});
    defer allocator.free(pdf_data);

    // Decode base64
    const decoded = try cdp.base64.decodeAlloc(allocator, pdf_data);
    defer allocator.free(decoded);

    std.debug.print("PDF: {} bytes\n", .{decoded.len});
}
```

## Paper Size

### Letter (US Standard)

```zig
const pdf = try page.printToPDF(allocator, .{
    .paper_width = 8.5,
    .paper_height = 11.0,
});
```

### A4 (International)

```zig
const pdf = try page.printToPDF(allocator, .{
    .paper_width = 8.27,
    .paper_height = 11.69,
});
```

### Legal

```zig
const pdf = try page.printToPDF(allocator, .{
    .paper_width = 8.5,
    .paper_height = 14.0,
});
```

### Custom Size

```zig
const pdf = try page.printToPDF(allocator, .{
    .paper_width = 5.0,  // inches
    .paper_height = 7.0,
});
```

## Orientation

### Portrait (default)

```zig
const pdf = try page.printToPDF(allocator, .{
    .landscape = false,
});
```

### Landscape

```zig
const pdf = try page.printToPDF(allocator, .{
    .landscape = true,
});
```

## Margins

```zig
const pdf = try page.printToPDF(allocator, .{
    .margin_top = 0.5,     // inches
    .margin_bottom = 0.5,
    .margin_left = 0.75,
    .margin_right = 0.75,
});
```

### No Margins

```zig
const pdf = try page.printToPDF(allocator, .{
    .margin_top = 0,
    .margin_bottom = 0,
    .margin_left = 0,
    .margin_right = 0,
});
```

## Backgrounds

Include background colors and images:

```zig
const pdf = try page.printToPDF(allocator, .{
    .print_background = true,
});
```

## Scale

```zig
// Shrink content to 80%
const pdf = try page.printToPDF(allocator, .{
    .scale = 0.8,
});

// Enlarge content to 120%
const pdf_large = try page.printToPDF(allocator, .{
    .scale = 1.2,
});
```

## Page Ranges

```zig
// First 3 pages
const pdf = try page.printToPDF(allocator, .{
    .page_ranges = "1-3",
});

// Specific pages
const pdf2 = try page.printToPDF(allocator, .{
    .page_ranges = "1,3,5-7",
});
```

## Headers and Footers

```zig
const pdf = try page.printToPDF(allocator, .{
    .display_header_footer = true,
    .header_template =
        \\<div style="font-size:10px; text-align:center; width:100%;">
        \\  <span class="title"></span>
        \\</div>
    ,
    .footer_template =
        \\<div style="font-size:10px; text-align:center; width:100%;">
        \\  Page <span class="pageNumber"></span> of <span class="totalPages"></span>
        \\</div>
    ,
    .margin_top = 1.0,    // Make room for header
    .margin_bottom = 1.0, // Make room for footer
});
```

### Template Variables

| Variable | Description |
|----------|-------------|
| `date` | Formatted date |
| `title` | Document title |
| `url` | Document URL |
| `pageNumber` | Current page |
| `totalPages` | Total pages |

## CSS Page Size

Prefer CSS `@page` rules:

```zig
const pdf = try page.printToPDF(allocator, .{
    .prefer_css_page_size = true,
});
```

## Complete Options

```zig
const pdf = try page.printToPDF(allocator, .{
    // Page setup
    .landscape = false,
    .paper_width = 8.5,
    .paper_height = 11.0,
    
    // Margins
    .margin_top = 0.5,
    .margin_bottom = 0.5,
    .margin_left = 0.5,
    .margin_right = 0.5,
    
    // Content
    .print_background = true,
    .scale = 1.0,
    .page_ranges = null, // All pages
    
    // Headers/Footers
    .display_header_footer = true,
    .header_template = "<div></div>",
    .footer_template = "<div>Page <span class='pageNumber'></span></div>",
    
    // CSS
    .prefer_css_page_size = false,
});
```

## HTML to PDF

Convert HTML string to PDF:

```zig
var page = cdp.Page.init(session);
try page.enable();

// Set HTML content
try page.setDocumentContent(
    \\<!DOCTYPE html>
    \\<html>
    \\<head>
    \\  <style>
    \\    body { font-family: Arial, sans-serif; }
    \\    h1 { color: navy; }
    \\  </style>
    \\</head>
    \\<body>
    \\  <h1>Report Title</h1>
    \\  <p>Generated content goes here.</p>
    \\</body>
    \\</html>
);

const pdf = try page.printToPDF(allocator, .{
    .print_background = true,
});
```

## Multiple Pages to PDF

```zig
const urls = [_][]const u8{
    "https://example.com/page1",
    "https://example.com/page2",
    "https://example.com/page3",
};

for (urls, 0..) |url, idx| {
    var session = try browser.newPage();
    defer session.detach() catch {};

    var page = cdp.Page.init(session);
    try page.enable();

    _ = try page.navigate(allocator, url);

    // Wait
    var i: u32 = 0;
    while (i < 500000) : (i += 1) {
        std.atomic.spinLoopHint();
    }

    const pdf = try page.printToPDF(allocator, .{});
    defer allocator.free(pdf);

    const decoded = try cdp.base64.decodeAlloc(allocator, pdf);
    defer allocator.free(decoded);

    std.debug.print("PDF {}: {} bytes\n", .{idx, decoded.len});
}
```
