//! Video recording and live-streaming module for cursor replay.
//!
//! Provides modular components for:
//! - Frame capture (CDP screenshots)
//! - Video encoding (FFmpeg pipe)
//! - Live streaming (HTTP MJPEG / WebSocket)
//! - Orchestration of capture with replay execution

pub const frame_capture = @import("frame_capture.zig");
pub const encoder = @import("encoder.zig");
pub const stream = @import("stream.zig");
pub const orchestrator = @import("orchestrator.zig");

// Re-export main types for convenience
pub const FrameCapture = frame_capture.FrameCapture;
pub const FrameCaptureConfig = frame_capture.FrameCaptureConfig;
pub const Frame = frame_capture.Frame;

pub const VideoEncoder = encoder.VideoEncoder;
pub const EncoderConfig = encoder.EncoderConfig;
pub const VideoFormat = encoder.VideoFormat;

pub const StreamServer = stream.StreamServer;
pub const StreamConfig = stream.StreamConfig;

pub const Orchestrator = orchestrator.Orchestrator;
pub const OutputMode = orchestrator.OutputMode;
pub const RecordConfig = orchestrator.RecordConfig;
