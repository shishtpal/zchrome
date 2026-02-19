const std = @import("std");

// ─── Public API Re-exports ──────────────────────────────────────────────────

// Browser launcher
pub const Browser = @import("browser/launcher.zig").Browser;
pub const findChrome = @import("browser/launcher.zig").findChrome;
pub const LaunchOptions = @import("browser/options.zig").LaunchOptions;
pub const Headless = @import("browser/options.zig").Headless;
pub const BrowserVersion = @import("browser/launcher.zig").BrowserVersion;
pub const TargetInfo = @import("browser/launcher.zig").TargetInfo;

// Core protocol
pub const Connection = @import("core/connection.zig").Connection;
pub const Session = @import("core/session.zig").Session;
pub const Event = @import("core/protocol.zig").Event;
pub const Response = @import("core/protocol.zig").Response;
pub const ErrorResponse = @import("core/protocol.zig").ErrorResponse;
pub const Message = @import("core/protocol.zig").Message;

// Core types
pub const types = @import("core/types.zig");

// Transport
pub const WebSocket = @import("transport/websocket.zig").WebSocket;
pub const PipeTransport = @import("transport/pipe.zig").PipeTransport;

// Domain clients
pub const Page = @import("domains/page.zig").Page;
pub const Runtime = @import("domains/runtime.zig").Runtime;
pub const Network = @import("domains/network.zig").Network;
pub const DOM = @import("domains/dom.zig").DOM;
pub const Input = @import("domains/input.zig").Input;
pub const Target = @import("domains/target.zig").Target;
pub const Emulation = @import("domains/emulation.zig").Emulation;
pub const Fetch = @import("domains/fetch.zig").Fetch;
pub const Performance = @import("domains/performance.zig").Performance;
pub const BrowserDomain = @import("domains/browser.zig").BrowserDomain;
pub const Storage = @import("domains/storage.zig").Storage;

// Utilities
pub const json = @import("util/json.zig");
pub const base64 = @import("util/base64.zig");
pub const url = @import("util/url.zig");
pub const retry = @import("util/retry.zig");

// ─── Error Sets ─────────────────────────────────────────────────────────────

pub const TransportError = error{
    ConnectionRefused,
    ConnectionClosed,
    ConnectionReset,
    HandshakeFailed,
    TlsError,
    FrameTooLarge,
    InvalidFrame,
    Timeout,
};

pub const ProtocolError = error{
    InvalidMessage,
    UnexpectedResponse,
    MissingField,
    TypeMismatch,
};

pub const CdpError = error{
    TargetCrashed,
    TargetClosed,
    SessionNotFound,
    MethodNotFound,
    InvalidParams,
    InternalError,
    GenericCdpError,
};

pub const LaunchError = error{
    ChromeNotFound,
    LaunchFailed,
    WsUrlParseError,
    StartupTimeout,
};

// ─── Version Info ───────────────────────────────────────────────────────────

pub const version = "0.1.0";
pub const protocol_version = "1.3";
