//! Cursor module - macro recording and replay functionality.
//!
//! This module provides:
//! - Recording browser interactions as reusable macros
//! - Replaying macros with assertion support
//! - Variable capture and comparison for testing
//!
//! Submodules:
//! - macro: MacroCommand types and file I/O
//! - state: Replay state and variable persistence
//! - record_server: WebSocket server for recording

const std = @import("std");

// Re-export from submodules (will be populated as we migrate)
pub const macro = @import("macro/mod.zig");
pub const state = @import("state.zig");
pub const record_server = @import("record_server.zig");
pub const utils = @import("utils.zig");
pub const assertions = @import("assertions.zig");
pub const actions = @import("actions.zig");
pub const display = @import("display.zig");
pub const record = @import("record.zig");
pub const replay = @import("replay/mod.zig");

// Re-export commonly used types
pub const MacroCommand = macro.MacroCommand;
pub const ActionType = macro.ActionType;
pub const CommandMacro = macro.CommandMacro;
pub const Macro = macro.Macro;
pub const MacroEvent = macro.MacroEvent;
pub const VarValue = state.VarValue;
pub const ReplayState = state.ReplayState;
pub const ReplayOptions = replay.ReplayOptions;
pub const ReplayInterval = replay.ReplayInterval;

// Re-export macro file I/O functions
pub const loadMacro = macro.loadMacro;
pub const saveMacro = macro.saveMacro;
pub const loadCommandMacro = macro.loadCommandMacro;
pub const saveCommandMacro = macro.saveCommandMacro;

// Public API
pub const cursor = replay.cursor;
pub const printCursorHelp = replay.printCursorHelp;
