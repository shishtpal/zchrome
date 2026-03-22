# Security Commands

Manage security state and certificate handling.

## Overview

```bash
zchrome security <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `state` | Show current security state |
| `ignore-certs` | Ignore certificate errors |
| `verify-certs` | Enable certificate verification (default) |

## security state

Show the current security state of the page.

```bash
zchrome security state
```

**Output (HTTPS):**

```
Security State
==============
URL: https://example.com/
Protocol: HTTPS (secure)
Security domain enabled. Security state changes will be reported via events.
```

**Output (HTTP):**

```
Security State
==============
URL: http://example.com/
Protocol: HTTP (insecure)
Warning: Connection is not encrypted.
```

## security ignore-certs

Ignore certificate errors. Useful for testing with self-signed certificates.

```bash
zchrome security ignore-certs
```

**Output:**

```
Certificate errors will now be IGNORED.
Warning: This makes connections vulnerable to MITM attacks.
Use this only for testing with self-signed certificates.
```

::: warning Security Risk
Using `ignore-certs` disables certificate verification, making connections vulnerable to man-in-the-middle attacks. Only use this for local development and testing.
:::

## security verify-certs

Re-enable certificate verification (default behavior).

```bash
zchrome security verify-certs
```

**Output:**

```
Certificate verification ENABLED (default behavior).
Invalid certificates will now cause connection failures.
```

## Interactive Mode

All security commands work in interactive mode:

```
zchrome> security state
Security State
==============
URL: https://localhost:8443/
Protocol: HTTPS (secure)

zchrome> security ignore-certs
Certificate errors will now be IGNORED.
Warning: This makes connections vulnerable to MITM attacks.

zchrome> navigate https://self-signed.badssl.com/
Navigated to: https://self-signed.badssl.com/
```

## Use Cases

### Testing with Self-Signed Certificates

```bash
# Start with local development server using self-signed cert
zchrome open

# Ignore certificate errors
zchrome security ignore-certs

# Navigate to local HTTPS server
zchrome navigate https://localhost:8443

# Run tests...

# Re-enable certificate verification when done
zchrome security verify-certs
```

### Checking Security State

```bash
# Navigate to a page
zchrome navigate https://example.com

# Check security state
zchrome security state
```

### Automated Testing Script

```bash
#!/bin/bash
# Test script for local HTTPS server

zchrome connect

# Allow self-signed certs for testing
zchrome security ignore-certs

# Run tests against local server
zchrome navigate https://localhost:3000
zchrome fill "#username" "testuser"
zchrome fill "#password" "testpass"
zchrome click "#login"
zchrome wait --text "Welcome"

# Verify we're on secure page
zchrome security state
```

## Notes

- Certificate verification is enabled by default
- The `ignore-certs` setting persists for the browser session
- Use `verify-certs` to restore default certificate checking
- Security state events are reported when the domain is enabled
