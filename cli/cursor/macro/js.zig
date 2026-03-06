//! JavaScript snippets for macro recording (legacy v1 event-based recording)
//!
//! These are injected into the page to capture raw mouse/keyboard events.

/// JavaScript code to inject for event recording (legacy v1)
pub const RECORD_INIT_JS =
    \\(function() {
    \\  if (window.__zchrome_macro) return 'already_initialized';
    \\  window.__zchrome_macro = {
    \\    events: [],
    \\    startTime: Date.now(),
    \\    recording: true
    \\  };
    \\  var m = window.__zchrome_macro;
    \\  function record(e) {
    \\    if (!m.recording) return;
    \\    var ev = {
    \\      type: e.type,
    \\      timestamp: Date.now() - m.startTime
    \\    };
    \\    if (e.clientX !== undefined) { ev.x = e.clientX; ev.y = e.clientY; }
    \\    if (e.button !== undefined) ev.button = e.button;
    \\    if (e.deltaX !== undefined) { ev.deltaX = e.deltaX; ev.deltaY = e.deltaY; }
    \\    if (e.key !== undefined) { ev.key = e.key; ev.code = e.code; }
    \\    ev.modifiers = (e.altKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.metaKey ? 4 : 0) | (e.shiftKey ? 8 : 0);
    \\    m.events.push(ev);
    \\  }
    \\  ['mousedown', 'mouseup', 'mousemove', 'wheel', 'keydown', 'keyup'].forEach(function(type) {
    \\    document.addEventListener(type, record, true);
    \\  });
    \\  return 'initialized';
    \\})()
;

/// JavaScript to retrieve recorded events
pub const RECORD_GET_EVENTS_JS =
    \\(function() {
    \\  if (!window.__zchrome_macro) return null;
    \\  window.__zchrome_macro.recording = false;
    \\  return JSON.stringify(window.__zchrome_macro.events);
    \\})()
;

/// JavaScript to retrieve and clear recorded events (for polling)
pub const RECORD_POLL_EVENTS_JS =
    \\(function() {
    \\  if (!window.__zchrome_macro) return null;
    \\  var events = window.__zchrome_macro.events;
    \\  window.__zchrome_macro.events = [];
    \\  return JSON.stringify(events);
    \\})()
;

/// JavaScript to clean up recording
pub const RECORD_CLEANUP_JS =
    \\(function() {
    \\  delete window.__zchrome_macro;
    \\  return 'cleaned';
    \\})()
;
