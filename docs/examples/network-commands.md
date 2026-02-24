# Network Commands

Intercept, block, mock, and inspect network requests from the CLI or interactive REPL.

## Route — Intercept Requests

Use `network route` to intercept requests matching a URL pattern. The command enters a live intercept loop and prints each matched request in real-time.

### Log Intercepted Requests

```bash
zchrome connect

zchrome navigate https://copilot.microsoft.com/

# Intercept and log all API calls (continue them normally)
zchrome network route "*api/*"
```

**Output:**

```
Route added: *api/* (continue/log)
Waiting for requests... (Ctrl+C to stop)
  INTERCEPTED: https://copilot.microsoft.com/c/api/start
  ...
```

### Block Requests

Block matching requests entirely — useful for disabling analytics, ads, or heavy resources.

```bash
# Block all PNG images
zchrome network route "*.png" --abort

# Block analytics
zchrome network route "*google-analytics*" --abort

# Block ads
zchrome network route "*doubleclick.net*" --abort
```

**Output:**

```
Route added: *.png (abort)
Waiting for requests... (Ctrl+C to stop)
  BLOCKED: https://example.com/images/hero.png
  BLOCKED: https://example.com/images/logo.png
```

### Mock Responses

Return custom JSON instead of making real network requests — useful for testing, prototyping, or offline development.

```bash
# Mock a user API endpoint
zchrome network route "*api/user*" --body "{\"name\":\"Test User\",\"id\":42}"

# Mock a config endpoint
zchrome network route "*api/config*" --body "{\"feature_flag\":true}"

# Mock from a file (reads file contents as response body)
zchrome network route "*api/config*" --file mock.json
```

**Output:**

```
Route added: *api/user* (mock response)
Waiting for requests... (Ctrl+C to stop)
  MOCKED: https://example.com/api/user/profile
```

Mock responses are returned with HTTP 200 and `Content-Type: application/json`.

### Redirect Requests

Redirect matching requests to a different host — useful for pointing production API calls to a local dev server or staging environment.

```bash
# Redirect all API calls to local dev server
zchrome network route "*api/*" --redirect "http://localhost:3000"

# Redirect to staging with a base path
zchrome network route "*api/v1/*" --redirect "http://staging.internal:8080/v2"
```

**Output:**

```
Route added: *api/* (redirect → http://localhost:3000)
Waiting for requests... (Ctrl+C to stop)
  REDIRECT: https://prod.example.com/api/users → http://localhost:3000/api/users
```

The original URL's path and query string are preserved; only the origin (and optional base path) is replaced.

## Unroute — Remove Routes

Remove all active intercept routes by disabling the Fetch domain.

```bash
zchrome network unroute
```

**Output:**

```
All routes removed
```

## Requests — View Tracked Requests

List network requests that have already completed on the current page. Uses the browser's Performance Resource Timing API.

### List All Requests

```bash
zchrome network requests
```

**Output:**

```
METHOD   URL                                                          STATUS
--------------------------------------------------------------------------------
fetch    https://api.example.com/v1/users                             45ms 1234B
script   https://cdn.example.com/app.js                               120ms 45678B
css      https://cdn.example.com/styles.css                           30ms 8901B

Total: 3 request(s)
```

### Filter by URL Pattern

Show only requests whose URL contains a substring.

```bash
# Show only API requests
zchrome network requests --filter "api"

# Show only image requests
zchrome network requests --filter ".png"
```

### Clear Request Log

Re-enable network tracking to clear the accumulated data.

```bash
zchrome network requests --clear
```

## Interactive REPL

All network commands work in the interactive REPL (also available as `net`):

```
zchrome> network route "*api*"
Route added: *api* (continue/log)
Waiting for requests... (Ctrl+C to stop)
  INTERCEPTED: https://example.com/api/data

zchrome> network unroute
All routes removed

zchrome> network requests --filter "cdn"
METHOD   URL                                                          STATUS
--------------------------------------------------------------------------------
script   https://cdn.example.com/app.js                               85ms 12345B

Total: 1 request(s)
```

## Use Cases

### Block Heavy Resources for Faster Scraping

```bash
# Block images to speed up page loads
zchrome network route "*.png" --abort
zchrome network route "*.jpg" --abort
zchrome network route "*.gif" --abort

# Navigate and scrape (much faster without images)
zchrome navigate https://example.com
zchrome get text "#content"

# Remove routes when done
zchrome network unroute
```

### Test API Error Handling

```bash
# Mock an error response
zchrome network route "*api/checkout*" --body "{\"error\":\"payment_failed\"}"

# Navigate and observe the UI error handling
zchrome navigate https://shop.example.com/checkout
zchrome snapshot -i
```

### Debug API Calls

```bash
# Watch what API calls a page makes
zchrome network route "*api*"
# Output shows each intercepted URL in real-time

# Or check what already loaded
zchrome network requests --filter "api"
```

### Offline Testing

```bash
# Block all external requests
zchrome network route "*" --abort

# Only local/cached content will load
zchrome navigate https://example.com
```

### A/B Test Feature Flags

```bash
# Mock feature flag endpoint
zchrome network route "*api/features*" --body "{\"new_checkout\":true,\"dark_mode\":false}"

# Navigate to see the app with different flags
zchrome navigate https://app.example.com
```

## URL Pattern Syntax

URL patterns use wildcard matching:

| Pattern | Matches |
|---------|---------|
| `*api*` | Any URL containing "api" |
| `*.png` | URLs ending in ".png" |
| `*example.com/api/*` | API paths on example.com |
| `*google-analytics*` | Google Analytics requests |
| `*/v1/users*` | Specific API endpoint path |

## Tips

1. **Route is blocking** — the `route` command enters a live loop. Press `Ctrl+C` to stop.
2. **One route at a time** — each `route` command sets up a new Fetch pattern. Use `unroute` between different routes.
3. **Requests shows completed resources** — it uses `performance.getEntriesByType('resource')`, so it only shows requests that already finished loading.
4. **Mock body is raw JSON** — no base64 encoding needed. The body is sent directly as the response.
5. **Use in scripts** — combine with `navigate`, `wait`, and `get` commands for automated testing workflows.
