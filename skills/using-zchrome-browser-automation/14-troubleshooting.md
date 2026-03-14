# Troubleshooting

## Chrome Not Installed / Not Found

**Symptoms:**
- `error: Chrome executable not found`
- `error: failed to spawn process`

**Causes & Solutions:**

1. **Chrome is not installed** — Install Chrome or Chromium from https://www.google.com/chrome/
2. **Chrome is installed but not in the default path** — Specify the path explicitly:
   ```bash
   # Windows
   zchrome open --chrome "C:\Program Files\Google\Chrome\Application\chrome.exe"
   zchrome open --chrome "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"

   # macOS
   zchrome open --chrome "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

   # Linux
   zchrome open --chrome /usr/bin/google-chrome
   zchrome open --chrome /usr/bin/chromium-browser
   ```
3. **Set it permanently via environment variable:**
   ```bash
   # PowerShell
   $env:ZCHROME_BROWSER = "C:\Program Files\Google\Chrome\Application\chrome.exe"

   # Bash
   export ZCHROME_BROWSER="/usr/bin/google-chrome"
   ```
4. **Chromium-based alternatives** — Edge, Brave, and other Chromium browsers also work:
   ```bash
   # Microsoft Edge
   zchrome open --chrome "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

   # Brave
   zchrome open --chrome "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
   ```

---

## Port Already in Use

**Symptoms:**
- `error: address already in use` on `zchrome open`
- Chrome fails to start with remote debugging

**Causes & Solutions:**

1. **Another Chrome instance is already using port 9222:**
   ```bash
   # Check what's using the port
   # Windows PowerShell
   Get-NetTCPConnection -LocalPort 9222

   # Linux/macOS
   lsof -i :9222
   ```
2. **Connect to the existing instance instead of launching a new one:**
   ```bash
   zchrome connect                    # Auto-discovers on default port
   zchrome connect --port 9222        # Explicit port
   ```
3. **Use a different port:**
   ```bash
   zchrome open --port 9333
   ```
4. **Kill the existing Chrome debug instance:**
   ```bash
   # Windows PowerShell
   Get-Process chrome | Where-Object { $_.CommandLine -match "remote-debugging-port" } | Stop-Process

   # Linux/macOS
   pkill -f "remote-debugging-port=9222"
   ```
5. **Use named sessions to run multiple instances on different ports:**
   ```bash
   zchrome --session project-a open --port 9222
   zchrome --session project-b open --port 9223
   ```

---

## Connection Refused

**Symptoms:**
- `error: connection refused`
- `error: unable to connect to 127.0.0.1:9222`

**Causes & Solutions:**

1. **Chrome is not running with remote debugging enabled:**
   ```bash
   # Start Chrome manually with debug port
   # Windows PowerShell
   & "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222

   # Or use zchrome to launch it
   zchrome open
   ```
2. **Verify Chrome is listening:**
   ```bash
   # PowerShell
   Invoke-RestMethod http://127.0.0.1:9222/json/version

   # curl
   curl http://127.0.0.1:9222/json/version
   ```
3. **Wrong port** — Make sure the port matches:
   ```bash
   zchrome connect --port 9222
   ```
4. **Firewall blocking the port** — Ensure localhost connections on the debug port are allowed.
5. **Chrome crashed or was closed** — Relaunch:
   ```bash
   zchrome open
   ```

---

## WebSocket URL Invalid or Stale

**Symptoms:**
- `error: WebSocket connection failed`
- Commands fail after Chrome was restarted

**Causes & Solutions:**

1. **Chrome was restarted** — The WebSocket URL changes each time Chrome starts. Reconnect:
   ```bash
   zchrome connect
   ```
2. **Stale `zchrome.json`** — Delete the config and reconnect:
   ```bash
   # Windows
   del zchrome.json
   zchrome connect

   # Linux/macOS
   rm zchrome.json
   zchrome connect
   ```

---

## Element Not Found

**Symptoms:**
- `error: element not found for selector: #my-element`
- Commands like `click`, `fill`, `get` fail

**Causes & Solutions:**

1. **Snapshot refs changed** — Element refs (`@e1`, `@e2`) are ephemeral and change when the page updates. Re-take the snapshot:
   ```bash
   zchrome snapshot -i
   ```
2. **Element hasn't loaded yet** — Wait for it first:
   ```bash
   zchrome wait "#my-element"
   zchrome click "#my-element"
   ```
3. **Element is inside an iframe** — zchrome operates on the main frame. Use `evaluate` to interact with iframe content.
4. **Selector is wrong** — Use `snapshot -i` to discover the correct selector or ref.

---

## Click Doesn't Work

**Symptoms:**
- `click` command succeeds but nothing happens on the page

**Causes & Solutions:**

1. **Element is off-screen** — Scroll it into view first:
   ```bash
   zchrome scrollintoview "#button"
   zchrome click "#button"
   ```
2. **Element is covered by another element** (modal, overlay, sticky header):
   ```bash
   # Check with highlight
   zchrome dev highlight "#button"
   # Close overlays first, or use JavaScript
   zchrome evaluate "document.querySelector('#button').click()"
   ```
3. **Element needs hover first** (dropdown menus):
   ```bash
   zchrome hover "#menu"
   zchrome click "#menu-item"
   ```

---

## Type / Fill Not Working

**Symptoms:**
- Text doesn't appear in the input field

**Causes & Solutions:**

1. **Element needs focus first:**
   ```bash
   zchrome focus "#input"
   zchrome type "#input" "hello"
   ```
2. **Input has existing content** — Use `fill` instead of `type` to clear first:
   ```bash
   zchrome fill "#input" "new value"
   ```
3. **React/Vue controlled input** — Some frameworks require dispatching input events. Try `fill` which simulates per-character typing.

---

## Memory Leaks in Debug Build

**Symptoms:**
- General Purpose Allocator reports memory leaks
- Slow performance in debug mode

**Solution:**
Build with optimizations:
```bash
zig build -Doptimize=ReleaseFast
```

---

## DNS / Hostname Not Resolving

**Symptoms:**
- `error: invalid IP address` when using hostnames

**Cause:** Zig 0.16's `std.Io.net.IpAddress.parse()` only accepts numeric IPs, not hostnames.

**Solution:** Use numeric IP addresses:
```bash
# Works
zchrome --url ws://127.0.0.1:9222/devtools/browser/xxx

# Does NOT work
zchrome --url ws://localhost:9222/devtools/browser/xxx
```

---

## Macro Recording Port Conflict

**Symptoms:**
- `cursor record` fails with port 4040 already in use

**Causes & Solutions:**

1. **Another recording session is running** — Stop it or use a different port.
2. **Another application is using port 4040:**
   ```bash
   # Check what's on port 4040
   # Windows
   Get-NetTCPConnection -LocalPort 4040

   # Linux/macOS
   lsof -i :4040
   ```

---

## Quick Reference Table

| Problem | Solution |
|---------|----------|
| Chrome not found | `--chrome <path>` or `$env:ZCHROME_BROWSER` |
| Port in use | `--port <other>` or `zchrome connect` to existing |
| Connection refused | Verify Chrome is running: `curl http://127.0.0.1:9222/json/version` |
| Stale WebSocket URL | `zchrome connect` (refreshes URL) |
| Element not found | Re-take `snapshot -i`; element refs are ephemeral |
| Click doesn't work | `scrollintoview` first; element may be covered |
| Type not working | `focus` before `type`; use `fill` to clear existing |
| Memory leaks (debug) | Build with `-Doptimize=ReleaseFast` |
| DNS not resolving | Use numeric IPs (`127.0.0.1` not `localhost`) |
