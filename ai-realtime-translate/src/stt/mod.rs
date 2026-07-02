//! Speech-to-text — sole backend is MLX-Whisper via the Python bridge.
//!
//! MLX-Whisper runs on Apple's MLX framework and uses the ANE/GPU. Models
//! are downloaded from HuggingFace and managed in the Models modal (see
//! `crate::llm::mlx_models::fetch_whisper_models`).
//!
//! `state.wmodel` is the full HF repo id (e.g. `mlx-community/whisper-large-v3-turbo`).
//! The toolbar dropdown only shows downloaded models; the full catalog lives
//! in the Models modal.

pub mod mlx_bridge;
pub mod prompts;

use crate::config::STT_TIMEOUT;
use crate::state::{AppEvent, AppState};
use anyhow::Result;
use std::time::Instant;
use tokio::time::timeout;

/// Transcribe a mono f32 chunk (`@ 16 kHz`) to text.
///
/// On error, logs to the UI and returns None so the pipeline can keep going.
pub async fn transcribe(
    state: AppState,
    chunk: Vec<f32>,
    src_lang: &str,
) -> Option<TranscribeResult> {
    if chunk.is_empty() {
        return None;
    }
    let snap = state.snapshot();
    if snap.wmodel.is_empty() {
        state.emit(AppEvent::Error {
            msg: "No Whisper model selected — open Models to download one".into(),
        });
        return None;
    }

    {
        let mut g = state.inner.lock();
        g.pub_state.stt_busy = true;
    }
    let started = Instant::now();
    let res = timeout(STT_TIMEOUT, async {
        if mlx_bridge::available() {
            mlx_bridge::transcribe(&chunk, &snap.wmodel, src_lang).await
        } else {
            Err(anyhow::anyhow!(
                "mlx-whisper not installed — `pip install mlx-whisper` into .venv"
            ))
        }
    })
    .await;
    {
        let mut g = state.inner.lock();
        g.pub_state.stt_busy = false;
    }
    let dt = started.elapsed().as_secs_f32();

    match res {
        Ok(Ok(mut r)) => {
            r.dt = dt;
            // Strip hallucinations using the same regex list as Python.
            r.text = crate::stt::prompts::strip_hallucinations(&r.text);
            if !r.text.is_empty() {
                state.emit(AppEvent::Info {
                    msg: format!("…{} ({:.1}s)", truncate(&r.text, 80), dt),
                });
            }
            Some(r)
        }
        Ok(Err(e)) => {
            state.emit(AppEvent::Error {
                msg: format!("STT: {e}"),
            });
            None
        }
        Err(_) => {
            state.emit(AppEvent::Error {
                msg: format!("STT timeout after {:.0}s", STT_TIMEOUT.as_secs_f32()),
            });
            None
        }
    }
}

#[derive(Debug, Clone)]
pub struct TranscribeResult {
    pub text: String,
    /// Detected source language code (e.g. `"en"`) returned by the STT
    /// engine. Consumers can use this to display the source language in
    /// the transcript UI; currently logged for diagnostics only.
    #[allow(dead_code)]
    pub language: Option<String>,
    pub dt: f32,
}

fn truncate(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        s.to_string()
    } else {
        let mut out: String = s.chars().take(n).collect();
        out.push('…');
        out
    }
}

/// Write a mono f32 chunk to a temporary WAV file and return the path.
#[allow(dead_code)] // reserved for a future whisper.cpp fallback
pub fn write_temp_wav(samples: &[f32]) -> Result<std::path::PathBuf> {
    let path = crate::config::temp_wav_path();
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: crate::config::SAMPLE_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(&path, spec)?;
    for &s in samples {
        let clamped = s.clamp(-1.0, 1.0);
        let i = (clamped * i16::MAX as f32) as i16;
        writer.write_sample(i)?;
    }
    writer.finalize()?;
    Ok(path)
}