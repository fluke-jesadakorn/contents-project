//! Translation backends — MLX-LM via Python bridge only.

pub mod benchmark;
pub mod mlx;
pub mod mlx_models;
pub mod prompts;

use crate::config::{
    LLM_MAX_RETRIES, TRANSLATION_MEMORY_SIZE,
};
use crate::state::{AppEvent, AppState, TranscriptEntry};
use std::time::Instant;

/// Translate one segment, with retry + validation.
///
/// The model is dispatched to MLX-LM (Apple Silicon). If MLX-LM isn't
/// installed, the call returns an error surfaced as a toast.
pub async fn translate(
    state: AppState,
    src: String,
    src_lang: String,
    tgt_lang: String,
    model: String,
) -> Option<TranscriptEntry> {
    if src.trim().is_empty() {
        return None;
    }
    let snap = state.snapshot();
    if model.is_empty() {
        state.emit(AppEvent::Info {
            msg: "…no translation model selected".into(),
        });
        return None;
    }
    if !mlx::available() {
        state.emit(AppEvent::Error {
            msg: "MLX-LM not available — pip install mlx-lm into the project .venv".into(),
        });
        return None;
    }

    let history = snap
        .history
        .iter()
        .rev()
        .take(TRANSLATION_MEMORY_SIZE)
        .cloned()
        .collect::<Vec<_>>();

    let prompt = prompts::build_translation_prompt(
        &src_lang,
        &tgt_lang,
        &snap.glossary,
        &snap.custom_prompt,
        snap.concise_translation,
    );
    let memory = if history.is_empty() {
        None
    } else {
        Some(prompts::memory_block(&history))
    };

    let started = Instant::now();
    let mut attempt = 0u32;
    let mut last_err: Option<String> = None;
    let mut translation = String::new();

    while attempt <= LLM_MAX_RETRIES {
        attempt += 1;
        {
            let mut g = state.inner.lock();
            g.pub_state.llm_busy = true;
        }
        let res = mlx::translate(&src, &model, &prompt, memory.as_deref()).await;
        {
            let mut g = state.inner.lock();
            g.pub_state.llm_busy = false;
        }
        match res {
            Ok(mut t) => {
                t = t.trim().to_string();
                if prompts::validate_translation(&src, &t, &src_lang, &tgt_lang) {
                    translation = t;
                    break;
                } else {
                    last_err = Some("validation failed".into());
                    if attempt > LLM_MAX_RETRIES {
                        translation = t;
                    }
                }
            }
            Err(e) => {
                last_err = Some(e.to_string());
                state.emit(AppEvent::Error {
                    msg: format!("LLM attempt {}: {}", attempt, e),
                });
            }
        }
    }

    let dt = started.elapsed().as_secs_f32();
    let entry = TranscriptEntry {
        ts: chrono::Utc::now().timestamp_millis() as f64 / 1000.0,
        src: src.clone(),
        tgt: translation.clone(),
        src_lang: src_lang.clone(),
        tgt_lang: tgt_lang.clone(),
        latency: crate::state::EntryLatency { stt: 0.0, llm: dt },
    };
    state.push_entry(entry.clone());
    if let Some(err) = last_err {
        if !translation.is_empty() {
            state.emit(AppEvent::Info {
                msg: format!("⚠ used last attempt despite {err}"),
            });
        }
    }
    Some(entry)
}