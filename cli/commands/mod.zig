//! Shared command implementations used by both CLI and interactive REPL.
//!
//! This module provides the command logic that can be reused across different
//! entry points (CLI args, interactive REPL, etc.).

const std = @import("std");

// ─── Private Submodule Imports ───────────────────────────────────────────────

const types_mod = @import("types.zig");
const helpers_mod = @import("helpers.zig");
const emulation_mod = @import("emulation.zig");
const navigation_mod = @import("navigation.zig");
const capture_mod = @import("capture.zig");
const cookies_mod = @import("cookies.zig");
const storage_mod = @import("storage.zig");
const evaluate_mod = @import("evaluate.zig");
const elements_mod = @import("elements.zig");
const scroll_mod = @import("scroll.zig");
const drag_mod = @import("drag.zig");
const upload_mod = @import("upload.zig");
const keyboard_mod = @import("keyboard.zig");
const mouse_mod = @import("mouse.zig");
const cursor_mod = @import("cursor.zig");
const wait_mod = @import("wait.zig");
const getters_mod = @import("getters.zig");
const setters_mod = @import("setters.zig");
const network_mod = @import("network.zig");
const dispatch_mod = @import("dispatch.zig");
const help_mod = @import("help.zig");

// ─── Type Re-exports ─────────────────────────────────────────────────────────

pub const CommandCtx = types_mod.CommandCtx;

// ─── Emulation Re-exports ────────────────────────────────────────────────────

pub const applyEmulationSettings = emulation_mod.applyEmulationSettings;
pub const applyUserAgent = emulation_mod.applyUserAgent;
pub const applyViewport = emulation_mod.applyViewport;
pub const applyGeolocation = emulation_mod.applyGeolocation;
pub const applyOfflineMode = emulation_mod.applyOfflineMode;
pub const applyMediaFeature = emulation_mod.applyMediaFeature;

// ─── Navigation Re-exports ───────────────────────────────────────────────────

pub const navigate = navigation_mod.navigate;
pub const back = navigation_mod.back;
pub const forward = navigation_mod.forward;
pub const reload = navigation_mod.reload;

// ─── Capture Re-exports ──────────────────────────────────────────────────────

pub const screenshot = capture_mod.screenshot;
pub const pdf = capture_mod.pdf;
pub const snapshot = capture_mod.snapshot;
pub const printSnapshotHelp = capture_mod.printSnapshotHelp;

// ─── Cookie Re-exports ───────────────────────────────────────────────────────

pub const cookies = cookies_mod.cookies;
pub const printCookiesHelp = cookies_mod.printCookiesHelp;

// ─── Storage Re-exports ──────────────────────────────────────────────────────

pub const webStorage = storage_mod.webStorage;
pub const printStorageHelp = storage_mod.printStorageHelp;

// ─── Evaluate Re-exports ─────────────────────────────────────────────────────

pub const evaluate = evaluate_mod.evaluate;

// ─── Element Re-exports ──────────────────────────────────────────────────────

pub const click = elements_mod.click;
pub const dblclick = elements_mod.dblclick;
pub const focus = elements_mod.focus;
pub const typeText = elements_mod.typeText;
pub const fill = elements_mod.fill;
pub const selectOption = elements_mod.selectOption;
pub const check = elements_mod.check;
pub const uncheck = elements_mod.uncheck;
pub const hover = elements_mod.hover;

// ─── Scroll Re-exports ───────────────────────────────────────────────────────

pub const scroll = scroll_mod.scroll;
pub const scrollIntoView = scroll_mod.scrollIntoView;

// ─── Drag Re-exports ─────────────────────────────────────────────────────────

pub const drag = drag_mod.drag;

// ─── Upload Re-exports ───────────────────────────────────────────────────────

pub const upload = upload_mod.upload;

// ─── Keyboard Re-exports ─────────────────────────────────────────────────────

pub const press = keyboard_mod.press;
pub const keyDown = keyboard_mod.keyDown;
pub const keyUp = keyboard_mod.keyUp;

// ─── Mouse Re-exports ────────────────────────────────────────────────────────

pub const mouse = mouse_mod.mouse;
pub const parseMouseButton = mouse_mod.parseMouseButton;
pub const printMouseHelp = mouse_mod.printMouseHelp;

// ─── Cursor Re-exports ───────────────────────────────────────────────────────

pub const cursor = cursor_mod.cursor;
pub const printCursorHelp = cursor_mod.printCursorHelp;

// ─── Macro Re-exports ────────────────────────────────────────────────────────

const macro_mod = @import("macro.zig");
pub const Macro = macro_mod.Macro;
pub const MacroEvent = macro_mod.MacroEvent;
pub const loadMacro = macro_mod.loadMacro;
pub const saveMacro = macro_mod.saveMacro;

// ─── Wait Re-exports ─────────────────────────────────────────────────────────

pub const wait = wait_mod.wait;
pub const printWaitHelp = wait_mod.printWaitHelp;

// ─── Getter Re-exports ───────────────────────────────────────────────────────

pub const get = getters_mod.get;
pub const printGetHelp = getters_mod.printGetHelp;

// ─── Setter Re-exports ───────────────────────────────────────────────────────

pub const set = setters_mod.set;
pub const printSetHelp = setters_mod.printSetHelp;

// ─── Dispatch Re-exports ─────────────────────────────────────────────────────

pub const dispatchSessionCommand = dispatch_mod.dispatchSessionCommand;

// ─── Help Re-exports ─────────────────────────────────────────────────────────

pub const printTabHelp = help_mod.printTabHelp;
pub const printWindowHelp = help_mod.printWindowHelp;

// ─── Network Re-exports ──────────────────────────────────────────────────────

pub const network = network_mod.network;
pub const printNetworkHelp = network_mod.printNetworkHelp;

// ─── Helper Re-exports ───────────────────────────────────────────────────────

pub const writeFile = helpers_mod.writeFile;
