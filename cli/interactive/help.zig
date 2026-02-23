//! Help text for the interactive REPL.
//!
//! This module contains the help text displayed when users run `help` or `?`
//! in interactive mode.

const std = @import("std");

pub fn print() void {
    std.debug.print(
        \\Commands:
        \\  help, ?               Show this help
        \\  quit, exit            Exit interactive mode
        \\  version               Show browser version
        \\  pages                 List open pages
        \\  use <target-id>       Switch to a different page
        \\  tab                   List open tabs (numbered)
        \\  tab new [url]         Open new tab
        \\  tab <n>               Switch to tab n
        \\  tab close [n]         Close tab n (default: current)
        \\  window new            Open new browser window
        \\
        \\Navigation:
        \\  navigate <url>        Navigate to URL (aliases: nav, goto)
        \\  back                  Go back in history
        \\  forward               Go forward in history
        \\  reload                Reload current page
        \\
        \\Capture:
        \\  screenshot [path]     Take screenshot (aliases: ss)
        \\  pdf [path]            Generate PDF
        \\  snapshot [opts]       Capture accessibility tree (aliases: snap)
        \\    Options: -i (interactive only), -c (compact), -d <n> (depth)
        \\
        \\Inspection:
        \\  evaluate <expr>       Evaluate JavaScript (aliases: eval, js)
        \\  dom <selector>        Query DOM element
        \\  cookies               List cookies (optional [domain])
        \\  cookies get <n> [d]   Get cookie by name (optional [domain])
        \\  cookies set <n> <v>   Set a cookie
        \\  cookies delete <n> [d] Delete cookie by name (optional [domain])
        \\  cookies clear [d]     Clear all cookies (optional [domain])
        \\  cookies export <p> [d] Export cookies to file (optional [domain])
        \\  cookies import <p> [d] Import cookies from file (optional [domain])
        \\  storage local         Get all localStorage (JSON)
        \\  storage local <key>   Get specific key
        \\  storage local set <k> <v>  Set value
        \\  storage local clear   Clear all localStorage
        \\  storage local export <file>  Export to JSON/YAML file
        \\  storage local import <file>  Import from JSON/YAML file
        \\  storage session [..]  Same for sessionStorage
        \\
        \\Element Actions:
        \\  click <selector>      Click element
        \\  dblclick <selector>   Double-click element
        \\  fill <sel> <text>     Clear and fill input
        \\  type <sel> <text>     Type text (append)
        \\  select <sel> <value>  Select dropdown option
        \\  check <selector>      Check checkbox
        \\  uncheck <selector>    Uncheck checkbox
        \\  hover <selector>      Hover over element
        \\  focus <selector>      Focus element
        \\  scroll <dir> [px]     Scroll page (up/down/left/right)
        \\  scrollinto <selector> Scroll element into view
        \\  drag <src> <tgt>      Drag element to target
        \\  upload <sel> <files>  Upload files to input
        \\
        \\Keyboard:
        \\  press <key>           Press key (Enter, Control+a) (alias: key)
        \\  keydown <key>         Hold key down
        \\  keyup <key>           Release key
        \\
        \\Mouse:
        \\  mouse move <x> <y>    Move mouse to coordinates
        \\  mouse down [button]   Press mouse button (left/right/middle)
        \\  mouse up [button]     Release mouse button
        \\  mouse wheel <dy> [dx] Scroll mouse wheel
        \\
        \\Getters:
        \\  get text <sel>        Get text content
        \\  get html <sel>        Get innerHTML
        \\  get value <sel>       Get input value
        \\  get attr <sel> <attr> Get attribute
        \\  get title             Get page title
        \\  get url               Get page URL
        \\  get count <sel>       Count matching elements
        \\  get box <sel>         Get bounding box
        \\
        \\Wait:
        \\  wait <selector>       Wait for element to be visible
        \\  wait <ms>             Wait for time (milliseconds)
        \\  wait --text "txt"     Wait for text to appear
        \\  wait --match "pat"    Wait for URL pattern (glob)
        \\  wait --load <state>   Wait for load state (load, domcontentloaded, networkidle)
        \\  wait --fn "expr"      Wait for JS condition to be true
        \\
        \\Selectors can be CSS selectors or @refs from snapshot (e.g., @e3)
        \\
    , .{});
}
