//! Browser element actions and getters.
//!
//! This module provides functions for interacting with web page elements
//! through the Chrome DevTools Protocol.

const std = @import("std");
const cdp = @import("cdp");

// Submodules
pub const types = @import("types.zig");
pub const helpers = @import("helpers.zig");
pub const selector = @import("selector.zig");
pub const element = @import("element.zig");
pub const upload = @import("upload.zig");
pub const getters = @import("getters.zig");

// Re-export types at root level for backward compatibility
pub const ResolvedElement = types.ResolvedElement;
pub const ElementPosition = types.ElementPosition;

// Re-export selector functions
pub const resolveSelector = selector.resolveSelector;

// Re-export element action functions
pub const getElementPosition = element.getElementPosition;
pub const getElementCenter = element.getElementCenter;
pub const clickElement = element.clickElement;
pub const focusElement = element.focusElement;
pub const typeText = element.typeText;
pub const clearField = element.clearField;
pub const fillElement = element.fillElement;
pub const hoverElement = element.hoverElement;
pub const selectOption = element.selectOption;
pub const setChecked = element.setChecked;
pub const scroll = element.scroll;
pub const scrollIntoView = element.scrollIntoView;
pub const dragElement = element.dragElement;

// Re-export upload function
pub const uploadFiles = upload.uploadFiles;

// Re-export getter functions
pub const getText = getters.getText;
pub const getHtml = getters.getHtml;
pub const getValue = getters.getValue;
pub const getAttribute = getters.getAttribute;
pub const getPageTitle = getters.getPageTitle;
pub const getPageUrl = getters.getPageUrl;
pub const getCount = getters.getCount;
pub const getStyles = getters.getStyles;
