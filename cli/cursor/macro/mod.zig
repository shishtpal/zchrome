//! Macro module - recording and playback data structures.
//!
//! This module provides types for representing recorded mouse/keyboard events
//! and semantic commands, with functions for loading/saving macros to JSON files.
//!
//! Two formats are supported:
//! - Version 1: Raw events (mouseMove, keyDown, etc.) - low-level, coordinate-based
//! - Version 2: Semantic commands (click, fill, press, etc.) - high-level, selector-based

const std = @import("std");

// Submodules
pub const command = @import("command.zig");
pub const event = @import("event.zig");
pub const js = @import("js.zig");

// ============================================================================
// Version 2: Semantic Commands (high-level, human-readable)
// ============================================================================

pub const ActionType = command.ActionType;
pub const MacroCommand = command.MacroCommand;
pub const CommandMacro = command.CommandMacro;
pub const saveCommandMacro = command.save;
pub const loadCommandMacro = command.load;

// ============================================================================
// Version 1: Raw Events (low-level, for backward compatibility)
// ============================================================================

pub const EventType = event.EventType;
pub const MouseButton = event.MouseButton;
pub const MacroEvent = event.MacroEvent;
pub const Macro = event.Macro;
pub const loadMacro = event.load;
pub const saveMacro = event.save;

// ============================================================================
// Recording JavaScript (legacy v1)
// ============================================================================

pub const RECORD_INIT_JS = js.RECORD_INIT_JS;
pub const RECORD_GET_EVENTS_JS = js.RECORD_GET_EVENTS_JS;
pub const RECORD_POLL_EVENTS_JS = js.RECORD_POLL_EVENTS_JS;
pub const RECORD_CLEANUP_JS = js.RECORD_CLEANUP_JS;
