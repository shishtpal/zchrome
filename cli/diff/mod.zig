//! Diff module for comparing snapshots and screenshots.
//!
//! Provides three main diff capabilities:
//! - Snapshot diff: Text-based diffing using Myers algorithm
//! - Screenshot diff: Pixel-level image comparison
//! - URL diff: Compare two URLs (snapshot and/or screenshot)

pub const myers = @import("myers.zig");
pub const colors = @import("colors.zig");
pub const snapshot = @import("snapshot.zig");
pub const image = @import("image.zig");
pub const png = @import("png.zig");
pub const url = @import("url.zig");

// Re-export commonly used types
pub const DiffEditType = myers.DiffEditType;
pub const DiffEdit = myers.DiffEdit;
pub const DiffResult = myers.DiffResult;
pub const myersDiff = myers.myersDiff;
pub const splitLines = myers.splitLines;

// Snapshot diff exports
pub const DiffSnapshotData = snapshot.DiffSnapshotData;
pub const diffSnapshots = snapshot.diffSnapshots;
pub const diffSnapshotCommand = snapshot.diffSnapshotCommand;
pub const printDiffSnapshotHelp = snapshot.printDiffSnapshotHelp;

// Image diff exports
pub const PixelDiffResult = image.PixelDiffResult;
pub const DiffScreenshotData = image.DiffScreenshotData;
pub const diffPixels = image.diffPixels;
pub const diffScreenshotCommand = image.diffScreenshotCommand;
pub const printDiffScreenshotHelp = image.printDiffScreenshotHelp;

// PNG helpers
pub const PngImage = png.PngImage;
pub const decodePng = png.decodePng;
pub const encodePng = png.encodePng;

// URL diff exports
pub const diffUrlCommand = url.diffUrlCommand;
pub const printDiffUrlHelp = url.printDiffUrlHelp;
