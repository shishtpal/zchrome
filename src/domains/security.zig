const std = @import("std");
const json = @import("json");
const Session = @import("../core/session.zig").Session;

// ─── Types ──────────────────────────────────────────────────────────────────

/// Security state of the page
pub const SecurityState = enum {
    unknown,
    neutral,
    insecure,
    secure,
    info,
    insecure_broken,

    pub fn fromString(s: []const u8) SecurityState {
        const map = std.StaticStringMap(SecurityState).initComptime(.{
            .{ "unknown", .unknown },
            .{ "neutral", .neutral },
            .{ "insecure", .insecure },
            .{ "secure", .secure },
            .{ "info", .info },
            .{ "insecure-broken", .insecure_broken },
        });
        return map.get(s) orelse .unknown;
    }
};

/// Certificate security state details
pub const CertificateSecurityState = struct {
    protocol: []const u8,
    key_exchange: []const u8,
    key_exchange_group: ?[]const u8 = null,
    cipher: []const u8,
    mac: ?[]const u8 = null,
    certificate: [][]const u8,
    subject_name: []const u8,
    issuer: []const u8,
    valid_from: f64,
    valid_to: f64,
    certificate_network_error: ?[]const u8 = null,
    certificate_has_weak_signature: bool = false,
    certificate_has_sha1_signature: bool = false,
    modern_ssl: bool = false,
    obsolete_ssl_protocol: bool = false,
    obsolete_ssl_key_exchange: bool = false,
    obsolete_ssl_cipher: bool = false,
    obsolete_ssl_signature: bool = false,

    pub fn deinit(self: *CertificateSecurityState, allocator: std.mem.Allocator) void {
        allocator.free(self.protocol);
        allocator.free(self.key_exchange);
        if (self.key_exchange_group) |g| allocator.free(g);
        allocator.free(self.cipher);
        if (self.mac) |m| allocator.free(m);
        for (self.certificate) |cert| allocator.free(cert);
        allocator.free(self.certificate);
        allocator.free(self.subject_name);
        allocator.free(self.issuer);
        if (self.certificate_network_error) |e| allocator.free(e);
    }
};

/// Visible security state of the page
pub const VisibleSecurityState = struct {
    security_state: SecurityState,
    certificate_security_state: ?CertificateSecurityState = null,
    security_state_issue_ids: [][]const u8 = &.{},

    pub fn deinit(self: *VisibleSecurityState, allocator: std.mem.Allocator) void {
        if (self.certificate_security_state) |*css| css.deinit(allocator);
        for (self.security_state_issue_ids) |id| allocator.free(id);
        if (self.security_state_issue_ids.len > 0) {
            allocator.free(self.security_state_issue_ids);
        }
    }
};

/// Action to take on certificate error
pub const CertificateErrorAction = enum {
    @"continue",
    cancel,

    pub fn toString(self: CertificateErrorAction) []const u8 {
        return switch (self) {
            .@"continue" => "continue",
            .cancel => "cancel",
        };
    }
};

// ─── Security Domain Client ─────────────────────────────────────────────────

/// Security domain client for handling certificate and security state
pub const Security = struct {
    session: *Session,

    const Self = @This();

    pub fn init(session: *Session) Self {
        return .{ .session = session };
    }

    /// Enable security domain events
    pub fn enable(self: *Self) !void {
        var result = try self.session.sendCommand("Security.enable", .{});
        result.deinit(self.session.allocator);
    }

    /// Disable security domain
    pub fn disable(self: *Self) !void {
        try self.session.sendCommandIgnoreResult("Security.disable", .{});
    }

    /// Enable/disable whether all certificate errors should be ignored.
    /// This is useful for testing with self-signed certificates.
    pub fn setIgnoreCertificateErrors(self: *Self, ignore: bool) !void {
        try self.session.sendCommandIgnoreResult("Security.setIgnoreCertificateErrors", .{
            .ignore = ignore,
        });
    }

    /// Handle a certificate error that was raised as an event.
    /// Only valid if setOverrideCertificateErrors was called with true.
    pub fn handleCertificateError(self: *Self, event_id: i64, action: CertificateErrorAction) !void {
        try self.session.sendCommandIgnoreResult("Security.handleCertificateError", .{
            .eventId = event_id,
            .action = action.toString(),
        });
    }

    /// Enable certificate error overriding. When enabled, certificate errors
    /// will pause navigation and send a certificateError event instead of
    /// showing the certificate error page.
    pub fn setOverrideCertificateErrors(self: *Self, override: bool) !void {
        try self.session.sendCommandIgnoreResult("Security.setOverrideCertificateErrors", .{
            .override = override,
        });
    }
};

// ─── Event Types ────────────────────────────────────────────────────────────

/// Fired when the security state of the page changes
pub const SecurityStateChangedEvent = struct {
    security_state: SecurityState,
    scheme_is_cryptographic: bool = false,
    explanations: []SecurityStateExplanation = &.{},
    insecure_content_status: ?InsecureContentStatus = null,
    summary: ?[]const u8 = null,

    pub fn deinit(self: *SecurityStateChangedEvent, allocator: std.mem.Allocator) void {
        for (self.explanations) |*exp| exp.deinit(allocator);
        if (self.explanations.len > 0) allocator.free(self.explanations);
        if (self.summary) |s| allocator.free(s);
    }
};

/// Explanation for security state
pub const SecurityStateExplanation = struct {
    security_state: SecurityState,
    title: []const u8,
    summary: []const u8,
    description: []const u8,
    mixed_content_type: []const u8 = "",
    certificate: [][]const u8 = &.{},
    recommendations: [][]const u8 = &.{},

    pub fn deinit(self: *SecurityStateExplanation, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.summary);
        allocator.free(self.description);
        if (self.mixed_content_type.len > 0) allocator.free(self.mixed_content_type);
        for (self.certificate) |cert| allocator.free(cert);
        if (self.certificate.len > 0) allocator.free(self.certificate);
        for (self.recommendations) |rec| allocator.free(rec);
        if (self.recommendations.len > 0) allocator.free(self.recommendations);
    }
};

/// Status of insecure content on the page
pub const InsecureContentStatus = struct {
    ran_mixed_content: bool = false,
    displayed_mixed_content: bool = false,
    contained_mixed_form: bool = false,
    ran_content_with_cert_errors: bool = false,
    displayed_content_with_cert_errors: bool = false,
    ran_insecure_content_style: SecurityState = .unknown,
    displayed_insecure_content_style: SecurityState = .unknown,
};

/// Certificate error event
pub const CertificateErrorEvent = struct {
    event_id: i64,
    error_type: []const u8,
    request_url: []const u8,

    pub fn deinit(self: *CertificateErrorEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.error_type);
        allocator.free(self.request_url);
    }
};
