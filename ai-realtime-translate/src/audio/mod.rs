//! Audio pipeline — two capture sources feeding the same VAD → denoise path:
//!   1. `cpal` input device (microphone or virtual audio device like BlackHole 2ch).
//!   2. `ScreenCaptureKit` system audio (same engine OBS uses on macOS 13+).
//!
//! Both sources normalise to mono f32 at the device's native sample rate and
//! feed it into the shared VSM. The pipeline then resamples to SAMPLE_RATE
//! for the STT stage.

pub mod capture;
pub mod denoise;
#[cfg(target_os = "macos")]
pub mod output;
pub mod pipeline;
pub mod system_capture;
pub mod vad;

#[cfg(target_os = "macos")]
pub use system_capture::SystemAudioCapture;

/// Sentinel device name used in the UI dropdown to request system audio
/// capture via ScreenCaptureKit.
pub const SYSTEM_AUDIO_DEVICE: &str = "System Audio (ScreenCaptureKit)";

/// User-facing label for the SCK pseudo-device in the Audio Input dropdown.
/// Slightly friendlier than the raw `SYSTEM_AUDIO_DEVICE` constant — the
/// word "Mac" anchors what it captures and the "(no setup)" tells the user
/// they don't need BlackHole / Multi-Output / any virtual audio driver.
pub const SYSTEM_AUDIO_DISPLAY: &str = "★ Mac Speaker Audio (no setup)";