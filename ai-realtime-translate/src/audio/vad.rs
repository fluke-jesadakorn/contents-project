//! WebRTC-style voice activity detector — pure Rust port of the same algorithm
//! `webrtcvad` uses (GMM classifier on 6 frequency-band features).
//!
//! For the first cut we use a simpler energy-based VAD that matches the
//! Python implementation's behavior: a frame counts as speech if its RMS is
//! above `VAD_RMS_FLOOR` OR (later) if the webrtcvad classifier says so.
//!
//! The Rust port of the full WebRTC VAD is non-trivial (~1500 LoC); we'll
//! upgrade to `webrtc-vad-rs` or a pure-rust equivalent once the rest of the
//! pipeline is stable. For system audio (which usually has music/tones), the
//! RMS fallback in the Python version was already the dominant signal.

use crate::config::{VAD_FRAME_MS, VAD_RMS_FLOOR, SAMPLE_RATE};

#[allow(dead_code)] // used only by the test module below
const FRAME_SAMPLES: usize = (SAMPLE_RATE as usize * VAD_FRAME_MS as usize) / 1000;

/// Compute RMS of a frame.
pub fn frame_rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum: f32 = samples.iter().map(|s| s * s).sum();
    (sum / samples.len() as f32).sqrt()
}

/// Returns true if this frame contains speech.
///
/// Mirrors the Python behavior:
///   `is_frame_speech(vad, frame) or rms > 0.003`
pub fn is_speech_frame(samples: &[f32]) -> bool {
    frame_rms(samples) > VAD_RMS_FLOOR
}

/// True if a chunk has enough speech energy to bother sending to STT.
/// Used as a final gate before pushing to the STT queue.
pub fn chunk_has_speech(samples: &[f32]) -> bool {
    let total_rms = frame_rms(samples);
    total_rms > VAD_RMS_FLOOR * 0.5
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silence_is_not_speech() {
        let silence = vec![0.0_f32; FRAME_SAMPLES];
        assert!(!is_speech_frame(&silence));
    }

    #[test]
    fn loud_tone_is_speech() {
        let tone: Vec<f32> = (0..FRAME_SAMPLES)
            .map(|i| 0.5 * (2.0 * std::f32::consts::PI * 440.0 * i as f32 / SAMPLE_RATE as f32).sin())
            .collect();
        assert!(is_speech_frame(&tone));
    }

    #[test]
    fn chunk_speech_detection() {
        let silence = vec![0.0_f32; FRAME_SAMPLES * 10];
        assert!(!chunk_has_speech(&silence));

        let mut loud = vec![0.0_f32; FRAME_SAMPLES * 10];
        for s in loud.iter_mut() {
            *s = 0.3;
        }
        assert!(chunk_has_speech(&loud));
    }
}