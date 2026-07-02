//! MLX-Whisper bridge — invokes the existing Python venv's `mlx_whisper` so we
//! get Apple Neural Engine acceleration without re-implementing MLX in Rust.
//!
//! The venv at `<project>/.venv` already has `mlx-whisper` installed (see
//! README.md), so we just run:
//!
//!   .venv/bin/python -c "import mlx_whisper, sys, json; \
//!       print(json.dumps(mlx_whisper.transcribe( \
//!           ..., path_or_hf_repo=..., language=...)))"
//!
//! We serialise the f32 samples as a base64-encoded little-endian blob on
//! stdin to avoid writing a temp file.

use super::TranscribeResult;
use anyhow::{anyhow, Result};
use base64::Engine;
use once_cell::sync::Lazy;
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

static VENV_PY: Lazy<Option<PathBuf>> = Lazy::new(|| {
    // Walk up from CARGO_MANIFEST_DIR to find the project's .venv.
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for ancestor in manifest.ancestors() {
        let cand = ancestor.join(".venv/bin/python");
        if cand.exists() {
            return Some(cand);
        }
    }
    // Fallback: try PATH.
    None
});

pub fn available() -> bool {
    VENV_PY.is_some()
}

pub fn probe() -> (bool, bool) {
    // (mlx_whisper, mlx_lm) — run a one-shot import check.
    let Some(py) = VENV_PY.as_ref() else {
        return (false, false);
    };
    let out = std::process::Command::new(py)
        .arg("-c")
        .arg("import mlx_whisper, sys; print('whisper_ok')")
        .output();
    let mlx_whisper = matches!(out, Ok(o) if o.status.success());
    let out = std::process::Command::new(py)
        .arg("-c")
        .arg("import mlx_lm; print('lm_ok')")
        .output();
    let mlx_lm = matches!(out, Ok(o) if o.status.success());
    (mlx_whisper, mlx_lm)
}

/// Transcribe `samples` (mono f32 @ 16 kHz) using the MLX-Whisper HF repo
/// named by `hf_repo` (e.g. `mlx-community/whisper-large-v3-turbo`).
pub async fn transcribe(samples: &[f32], hf_repo: &str, lang: &str) -> Result<TranscribeResult> {
    let py = VENV_PY
        .as_ref()
        .ok_or_else(|| anyhow!("venv python not found"))?;

    // Encode samples as base64 little-endian f32.
    let mut bytes = Vec::with_capacity(samples.len() * 4);
    for &s in samples {
        bytes.extend_from_slice(&s.to_le_bytes());
    }
    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);

    let lang_arg = match lang {
        "auto" | "" => "None".to_string(),
        other => format!("\"{}\"", other),
    };

    let script = format!(
        r#"
import sys, json, base64, numpy as np, mlx_whisper
samples = np.frombuffer(base64.b64decode(sys.stdin.read()), dtype=np.float32)
result = mlx_whisper.transcribe(
    samples,
    path_or_hf_repo="{repo}",
    language={lang},
    verbose=False,
)
print(json.dumps({{"text": result.get("text", ""), "language": result.get("language")}}, ensure_ascii=False))
"#,
        repo = hf_repo,
        lang = lang_arg,
    );

    let mut cmd = Command::new(py);
    cmd.arg("-c").arg(&script);
    cmd.stdin(Stdio::piped());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());
    cmd.kill_on_drop(true);

    let mut child = cmd.spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(b64.as_bytes()).await?;
        drop(stdin);
    }
    let out = child.wait_with_output().await?;
    if !out.status.success() {
        return Err(anyhow!(
            "mlx_whisper failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    let parsed: serde_json::Value = serde_json::from_slice(&out.stdout)
        .map_err(|e| anyhow!("mlx_whisper returned bad json: {e}"))?;
    let text = parsed
        .get("text")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    let language = parsed
        .get("language")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    Ok(TranscribeResult {
        text,
        language,
        dt: 0.0,
    })
}