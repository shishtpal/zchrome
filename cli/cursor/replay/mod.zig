//! Macro replay module with assertion and retry support.
//!
//! This module provides:
//! - CLI entry point for cursor replay commands
//! - Replay execution with retry logic and video recording
//! - Per-action handlers for macro commands
//! - JSON utilities for extraction and serialization
//! - Variable interpolation for dynamic values
//!
//! Submodules:
//! - cli: CLI entry point and help
//! - executor: Core replay loop
//! - actions: Per-action command handlers
//! - json: JSON extraction and serialization utilities
//! - interpolate: Variable interpolation

const std = @import("std");

// Submodules
pub const cli = @import("cli.zig");
pub const executor = @import("executor.zig");
pub const actions = @import("actions.zig");
pub const json_utils = @import("json.zig");
pub const interpolate = @import("interpolate.zig");

// Re-export command context from types
const types = @import("../../commands/types.zig");
pub const CommandCtx = types.CommandCtx;

// ============================================================================
// Public Types
// ============================================================================

pub const ReplayInterval = cli.ReplayInterval;
pub const ReplayOptions = cli.ReplayOptions;
pub const MarkError = actions.MarkError;
pub const ActionContext = actions.ActionContext;

// ============================================================================
// Public Functions
// ============================================================================

/// Main cursor command entry point
pub const cursor = cli.cursor;

/// Print cursor help text
pub const printCursorHelp = cli.printCursorHelp;

/// Execute macro commands with full options (retry, video, state management)
pub const replayCommandsWithOptions = executor.replayCommandsWithOptions;

/// Execute a single command
pub const executeCommand = actions.executeCommand;

/// Interpolate variables in a string
pub const interpolateVariables = interpolate.interpolateVariables;

/// Extract multiple fields using selector map
pub const extractFields = json_utils.extractFields;

/// Append JSON with optional deduplication
pub const appendWithDedupe = json_utils.appendWithDedupe;
