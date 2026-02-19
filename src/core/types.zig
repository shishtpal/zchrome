/// CDP primitive type aliases
/// These provide semantic meaning to string IDs used throughout CDP

/// Session identifier for target-attached sessions
pub const SessionId = []const u8;

/// Target identifier (browser tab, worker, etc.)
pub const TargetId = []const u8;

/// Frame identifier (iframe within a page)
pub const FrameId = []const u8;

/// Loader identifier (document load)
pub const LoaderId = []const u8;

/// Network request identifier
pub const RequestId = []const u8;

/// DOM node identifier
pub const NodeId = i64;

/// Remote object identifier (for Runtime)
pub const RemoteObjectId = []const u8;

/// Execution context identifier
pub const ExecutionContextId = i64;

/// Timestamp in milliseconds since epoch
pub const TimeSinceEpoch = f64;

/// Monotonic timestamp in milliseconds
pub const MonotonicTime = f64;

/// Command identifier (monotonically increasing)
pub const CommandId = u64;
