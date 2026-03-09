# Environment Variables

zchrome supports environment variables to configure defaults without repeating command-line flags. This is especially useful for CI/CD pipelines, Docker containers, and persistent shell configurations.

## Supported Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `ZCHROME_SESSION` | string | Default session name | `"default"` |
| `ZCHROME_BROWSER` | path | Chrome executable path | auto-detect |
| `ZCHROME_PORT` | number | Debug port | `9222` |
| `ZCHROME_DATA_DIR` | path | Chrome user data directory | session-specific |
| `ZCHROME_VERBOSE` | bool | Enable verbose output (`1` or `true`) | `false` |
| `ZCHROME_HEADLESS` | string | Headless mode: `new`, `old`, or `off` | `off` |
| `ZCHROME_PROVIDER` | string | Cloud provider: `local`, `kernel`, `notte`, `browserbase` | `local` |
| `ZCHROME_KERNEL_API_KEY` | string | Kernel.sh API key | - |
| `ZCHROME_NOTTE_API_KEY` | string | Notte.cc API key | - |
| `ZCHROME_BROWSERBASE_API_KEY` | string | Browserbase API key | - |

## Priority Order

Settings are resolved in this order (highest to lowest priority):

1. **Command-line flags** - Always take precedence
2. **Environment variables** - Applied if CLI flag not provided
3. **Session config** (`zchrome.json`) - Applied if neither CLI nor env var set
4. **Default values** - Built-in fallbacks

```
CLI flag > Environment variable > Session config > Default
```

## Setting Environment Variables

### Windows (PowerShell)

```powershell
# Set for current session
$env:ZCHROME_SESSION = "dev"
$env:ZCHROME_BROWSER = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$env:ZCHROME_PORT = "9223"
$env:ZCHROME_VERBOSE = "1"
$env:ZCHROME_HEADLESS = "new"

# Verify
zchrome open
```

To persist across sessions, add to your PowerShell profile (`$PROFILE`):

```powershell
$env:ZCHROME_BROWSER = "C:\Program Files\Google\Chrome\Application\chrome.exe"
```

### Windows (Command Prompt)

```cmd
set ZCHROME_SESSION=dev
set ZCHROME_BROWSER=C:\Program Files\Google\Chrome\Application\chrome.exe
set ZCHROME_PORT=9223

zchrome open
```

### Linux / macOS

```bash
export ZCHROME_SESSION="dev"
export ZCHROME_BROWSER="/usr/bin/google-chrome"
export ZCHROME_PORT="9223"
export ZCHROME_VERBOSE="true"
export ZCHROME_HEADLESS="new"

zchrome open
```

To persist, add to `~/.bashrc`, `~/.zshrc`, or `~/.profile`:

```bash
export ZCHROME_BROWSER="/usr/bin/google-chrome"
```

## Variable Details

### ZCHROME_SESSION

Sets the default session name. Equivalent to `--session <name>`.

```bash
export ZCHROME_SESSION="work"
zchrome navigate https://example.com  # Uses "work" session
```

See [CLI Sessions](/guide/cli-sessions) for more about sessions.

### ZCHROME_BROWSER

Path to Chrome executable. Useful when Chrome is installed in a non-standard location.

```bash
# Linux - Chromium
export ZCHROME_BROWSER="/usr/bin/chromium-browser"

# macOS - Chrome Canary
export ZCHROME_BROWSER="/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"

# Windows - Chrome Beta
$env:ZCHROME_BROWSER = "C:\Program Files\Google\Chrome Beta\Application\chrome.exe"
```

### ZCHROME_PORT

Default debug port. Useful when running multiple Chrome instances or when port 9222 is unavailable.

```bash
export ZCHROME_PORT="9223"
zchrome open  # Launches on port 9223
```

### ZCHROME_DATA_DIR

Chrome user data directory. Sets where Chrome stores profiles, cookies, and cache.

```bash
export ZCHROME_DATA_DIR="/tmp/chrome-test-profile"
zchrome open
```

### ZCHROME_VERBOSE

Enable verbose output for debugging. Set to `1` or `true`.

```bash
export ZCHROME_VERBOSE="1"
zchrome connect  # Shows detailed connection info
```

### ZCHROME_HEADLESS

Run Chrome in headless mode. Values: `new` (recommended), `old`, or `off`.

```bash
export ZCHROME_HEADLESS="new"
zchrome open  # Launches headless Chrome
```

### ZCHROME_PROVIDER

Set the default cloud browser provider. Values: `local` (default), `kernel`, `notte`, `browserbase`.

```bash
export ZCHROME_PROVIDER="kernel"
zchrome navigate https://example.com  # Uses Kernel.sh cloud browser
```

See [Cloud Providers](/cli/providers) for detailed provider documentation.

### ZCHROME_KERNEL_API_KEY

API key for [Kernel.sh](https://kernel.sh) cloud browser provider.

```bash
export ZCHROME_KERNEL_API_KEY="your-api-key"
zchrome provider set kernel
```

### ZCHROME_NOTTE_API_KEY

API key for [Notte.cc](https://notte.cc) cloud browser provider.

```bash
export ZCHROME_NOTTE_API_KEY="your-api-key"
zchrome provider set notte
```

### ZCHROME_BROWSERBASE_API_KEY

API key for [Browserbase](https://browserbase.com) cloud browser provider.

```bash
export ZCHROME_BROWSERBASE_API_KEY="your-api-key"
zchrome provider set browserbase
```

## CI/CD Examples

### GitHub Actions (Local Chrome)

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      ZCHROME_HEADLESS: "new"
      ZCHROME_BROWSER: "/usr/bin/google-chrome"
    steps:
      - uses: actions/checkout@v4
      - name: Install Chrome
        run: |
          sudo apt-get update
          sudo apt-get install -y google-chrome-stable
      - name: Run browser tests
        run: |
          zchrome open
          zchrome navigate https://example.com
          zchrome screenshot --output test.png
```

### GitHub Actions (Cloud Provider)

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      ZCHROME_PROVIDER: kernel
      ZCHROME_KERNEL_API_KEY: ${{ secrets.KERNEL_API_KEY }}
    steps:
      - uses: actions/checkout@v4
      - name: Run browser tests
        run: |
          # No Chrome install needed - using cloud browser
          zchrome --cleanup navigate https://example.com
          zchrome --cleanup screenshot --output test.png
```

### Docker

```dockerfile
FROM debian:bookworm-slim

# Install Chrome
RUN apt-get update && apt-get install -y \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV ZCHROME_BROWSER=/usr/bin/chromium
ENV ZCHROME_HEADLESS=new
ENV ZCHROME_DATA_DIR=/tmp/chrome-profile

COPY zchrome /usr/local/bin/
```

```bash
docker run --rm myimage zchrome open
```

### GitLab CI

```yaml
test:
  image: node:18
  variables:
    ZCHROME_HEADLESS: "new"
    ZCHROME_BROWSER: "/usr/bin/chromium-browser"
  before_script:
    - apt-get update && apt-get install -y chromium
  script:
    - zchrome open
    - zchrome navigate https://example.com
    - zchrome screenshot --output screenshot.png
```

## Combining with CLI Flags

CLI flags always override environment variables:

```bash
export ZCHROME_PORT="9222"
zchrome open --port 9223  # Uses 9223, not 9222
```

This allows you to set sensible defaults via environment while still overriding when needed.
