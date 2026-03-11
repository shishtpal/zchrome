//! Pipe-based Chrome communication module.
//!
//! This module provides pipe-based communication with Chrome using
//! --remote-debugging-pipe for extension loading via CDP.

const std = @import("std");

pub const launcher = @import("launcher.zig");
pub const extensions = @import("extensions.zig");

// Re-export main types
pub const ChromePipe = launcher.ChromePipe;
pub const loadExtension = extensions.loadExtension;
pub const unloadExtension = extensions.unloadExtension;
pub const getExtensions = extensions.getExtensions;
