# Security Domain

The `Security` domain provides methods for handling security state and certificate errors.

## Import

```zig
const cdp = @import("cdp");
const Security = cdp.Security;
```

## Initialization

```zig
var session = try browser.newPage();
var security = Security.init(session);
try security.enable();
```

## Methods

### enable

Enable security domain events.

```zig
pub fn enable(self: *Security) !void
```

### disable

Disable security domain.

```zig
pub fn disable(self: *Security) !void
```

### setIgnoreCertificateErrors

Enable or disable ignoring certificate errors. Useful for testing with self-signed certificates.

```zig
pub fn setIgnoreCertificateErrors(self: *Security, ignore: bool) !void
```

**Warning:** Setting `ignore` to `true` makes connections vulnerable to man-in-the-middle attacks. Only use for local development/testing.

### handleCertificateError

Handle a certificate error event.

```zig
pub fn handleCertificateError(
    self: *Security,
    event_id: i64,
    action: CertificateErrorAction,
) !void
```

### setOverrideCertificateErrors

Enable certificate error overriding. When enabled, certificate errors pause navigation and send events instead of showing error pages.

```zig
pub fn setOverrideCertificateErrors(self: *Security, override: bool) !void
```

## Types

### SecurityState

```zig
pub const SecurityState = enum {
    unknown,
    neutral,
    insecure,
    secure,
    info,
    insecure_broken,
};
```

### CertificateErrorAction

```zig
pub const CertificateErrorAction = enum {
    @"continue",
    cancel,
};
```

### CertificateSecurityState

```zig
pub const CertificateSecurityState = struct {
    protocol: []const u8,
    key_exchange: []const u8,
    cipher: []const u8,
    certificate: [][]const u8,
    subject_name: []const u8,
    issuer: []const u8,
    valid_from: f64,
    valid_to: f64,
    // ... additional fields
};
```

## Events

### securityStateChanged

Fired when the security state of the page changes.

### certificateError

Fired when a certificate error occurs (when override is enabled).

## Example

```zig
const cdp = @import("cdp");

pub fn allowSelfSignedCerts(session: *cdp.Session) !void {
    var security = cdp.Security.init(session);
    try security.enable();
    
    // Allow self-signed certificates for testing
    try security.setIgnoreCertificateErrors(true);
    
    // Navigate to HTTPS site with self-signed cert
    var page = cdp.Page.init(session);
    _ = try page.navigate(allocator, "https://localhost:8443");
}
```
