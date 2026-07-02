//! Shared config — values that previously lived at the top of `realtime_translator.py`.
//! All paths default to the standard Homebrew install locations on Apple Silicon.

use std::path::PathBuf;
use std::time::Duration;

/// Audio capture / STT sample rate. Whisper expects 16 kHz mono PCM.
pub const SAMPLE_RATE: u32 = 16_000;

/// Channel count — BlackHole 2ch is stereo but whisper wants mono.
pub const CAPTURE_CHANNELS: u16 = 2;

/// 100 ms blocks for the level meter + VAD sampling cadence.
pub const BLOCK_DURATION: Duration = Duration::from_millis(100);

/// WebRTC VAD frame size (must be 10/20/30 ms). Drives the test fixtures
/// in `audio::vad`; production uses RMS-only VAD for system audio.
#[allow(dead_code)]
pub const VAD_FRAME_MS: u32 = 30;

/// webrtcvad noise floor: frames with RMS > this count as "speech".
pub const VAD_RMS_FLOOR: f32 = 0.003;

/// Translation memory (last N segments fed to LLM as context).
pub const TRANSLATION_MEMORY_SIZE: usize = 5;

/// Sliding window kept for the UI's history panel.
pub const UI_HISTORY_LIMIT: usize = 200;

/// Working dir for transient WAV chunks. Used by `stt::write_temp_wav`.
#[allow(dead_code)]
pub fn temp_wav_path() -> PathBuf {
    std::env::temp_dir().join("foundry_live_chunk.wav")
}

/// Maximum retry attempts when the LLM produces garbage.
pub const LLM_MAX_RETRIES: u32 = 1;

/// STT timeout (mlx-whisper with large-v3-turbo on M-series ~5–10s/chunk).
pub const STT_TIMEOUT: Duration = Duration::from_secs(120);

// ─── Legacy whisper.cpp / mlx-tuning knobs ─────────────────────────────
//
// These were used by the original whisper.cpp + mlx-tuning Python stack.
// We're mlx-whisper-only now, so the constants are kept as documentation
// of what those defaults were, but nothing reads them. If/when we re-add
// whisper.cpp support, re-publish them.
#[allow(dead_code)]
mod legacy_whisper {
    use super::PathBuf;
    pub const STT_CHANNELS: u16 = 1;
    pub const VAD_AGGRESSIVENESS: u8 = 2;
    pub const LLM_NUM_PREDICT: u32 = 1024;
    pub const LLM_TEMPERATURE: f32 = 0.0;
    pub const LLM_SEED: u32 = 42;
    pub const LLM_REPEAT_PENALTY: f32 = 1.1;
    pub fn default_whisper_bin() -> PathBuf {
        PathBuf::from("/opt/homebrew/bin/whisper-cli")
    }
    pub fn default_whisper_model_dir() -> PathBuf {
        PathBuf::from("/opt/homebrew/share/whisper-cpp/models")
    }
}