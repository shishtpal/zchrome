# Chrome Options

Configure Chrome command-line arguments via `zchrome.json` to customize browser behavior when using `zchrome open`.

## Configuration

Add a `chrome_args` array to your `zchrome.json` file:

```json
{
  "port": 9222,
  "chrome_args": [
    "--disable-gpu",
    "--disable-infobars",
    "--no-sandbox",
    "--ignore-certificate-errors"
  ]
}
```

These arguments are appended to the Chrome launch command when you run:

```
zchrome open
```

## Available Options

### Performance & Stability
- `--disable-gpu`: Prevents GPU usage, reduces overhead in headless runs
- `--disable-dev-shm-usage`: Avoids shared memory issues in Docker/Linux environments
- `--disable-software-rasterizer`: Stops CPU rasterization fallback which can cause performance issues
- `--disable-renderer-backgrounding`: Keeps background tabs active for consistent behavior
- `--disable-background-networking`: Stops background network tasks like prefetching to reduce bandwidth
- `--disable-backgrounding-occluded-windows`: Prevents Chrome from deprioritizing background windows

### UI Suppression
- `--disable-infobars`: Removes the "Chrome is being controlled by automated software" banner
- `--disable-notifications`: Blocks pop-up notifications from appearing
- `--disable-extensions`: Prevents extensions from interfering with automation
- `--mute-audio`: Silences all audio during automated testing
- `--disable-popup-blocking`: Allows popups to appear (useful for testing popup behavior)
- `--disable-prompt-on-repost`: Stops warnings when reposting form data

### Security & Testing
- `--no-sandbox`: Required in some CI/CD setups (note: less secure, use with caution)
- `--ignore-certificate-errors`: Allows testing with self-signed certificates
- `--disable-web-security`: Enables cross-origin requests (for testing only)
- `--disable-sync`: Disables Chrome Sync to prevent data synchronization
- `--disable-hang-monitor`: Prevents Chrome from monitoring for hangs during automation

### Headless & Window
- `--headless=new`: Runs Chrome without visible UI (headless mode)
- `--window-size=1920,1080`: Ensures consistent viewport size for testing
- `--start-maximized`: Opens Chrome in full screen mode

### Features Control
- `--disable-features=Translate`: Turns off built-in translation features
- `--enable-features=NetworkService,NetworkServiceInProcess`: Forces newer network service architecture

### Metrics & Storage
- `--metrics-recording-only`: Collects metrics but doesn't upload them
- `--password-store=basic`: Uses basic password store instead of OS-specific password managers
- `--use-mock-keychain`: On macOS, avoids using the system keychain

### Startup Behavior
- `--remote-debugging-port=0`: Opens debugging port on a random available port
- `--no-first-run`: Skips the "first run" setup screen
- `--no-default-browser-check`: Prevents Chrome from asking to be the default browser
- `--disable-component-update`: Stops Chrome from updating built-in components
- `--disable-default-apps`: Disables installation of default apps

## Example Configurations

### CI/CD Environment

```json
{
  "chrome_args": [
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--disable-software-rasterizer"
  ]
}
```

### Automation Testing

```json
{
  "chrome_args": [
    "--disable-infobars",
    "--disable-notifications",
    "--disable-popup-blocking",
    "--ignore-certificate-errors"
  ]
}
```

### Headless with Fixed Viewport

```json
{
  "chrome_args": [
    "--headless=new",
    "--window-size=1920,1080",
    "--disable-gpu"
  ]
}
```

## Extension Loading

zchrome supports loading unpacked Chrome extensions. Starting with Chrome 137, Google removed the `--load-extension` flag from branded Chrome builds. zchrome provides two modes for extension loading via the `--via` flag.

### Extension Loading Modes

| Mode | Flag | Description |
|------|------|-------------|
| `port` | `--via=port` | **(Default)** Uses `--load-extension` with Chrome 137+ workaround |
| `pipe` | `--via=pipe` | Uses CDP `Extensions.loadUnpacked` via debugging pipe (experimental) |

### Port Mode (Default)

Port mode uses the traditional `--load-extension` CLI flag with an automatic workaround for Chrome 137+:

```bash
# Load an extension
zchrome extensions load /path/to/my-extension

# Launch Chrome (uses port mode by default)
zchrome open
```

Behind the scenes, zchrome adds `--disable-features=DisableLoadExtensionCommandLineSwitch` to re-enable the `--load-extension` flag on Chrome 137+.

### Pipe Mode (Experimental)

Pipe mode uses the Chrome DevTools Protocol `Extensions.loadUnpacked` method, which is the future-proof approach recommended by Google:

```bash
# Load extensions
zchrome extensions load /path/to/my-extension

# Launch with pipe mode
zchrome open --via=pipe
```

This mode:
- Uses `--remote-debugging-pipe` instead of `--remote-debugging-port`
- Adds `--enable-unsafe-extension-debugging` flag
- Loads extensions via CDP after Chrome starts

::: warning
Pipe mode is experimental and currently only supports POSIX systems (Linux, macOS).
:::

### Configuration

The `via` setting is saved to `zchrome.json` and used by subsequent commands:

```json
{
  "port": 9222,
  "via": "port",
  "extensions": [
    "/path/to/extension1",
    "/path/to/extension2"
  ]
}
```

### Extension Requirements

- Extensions require **headed mode** (headless is automatically disabled when extensions are configured)
- Extensions **cannot be used with cloud providers** (they require a local browser)
- Use absolute paths for extensions in config files
