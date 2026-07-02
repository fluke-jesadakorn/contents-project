//! Speed benchmarks for MLX chat + Whisper models.
//!
//! Both functions spawn a one-shot python subprocess that loads the
//! model, does a warmup pass, then a timed pass, and prints a
//! `SPEED:<value> <unit>` line on stdout. We parse that line and
//! return the formatted string for direct display in the Models modal.
//!
//! Caching: callers (the command driver in `app.rs`) write the result
//! into `state.model_speeds` / `state.wmodel_speeds` so subsequent
//! renders don't re-run the heavy load+inference pass.

use anyhow::{anyhow, Result};
use std::process::Stdio;
use tokio::io::AsyncReadExt;
use tokio::process::Command;

/// Run an MLX-LM generation benchmark on the given repo. Returns a
/// formatted speed string like `"32.4 tok/s"`. Errors propagate.
pub async fn benchmark_chat_model(repo: &str) -> Result<String> {
    let script = r#"
import sys, time
from mlx_lm import load, generate

model, tokenizer = load("REPO")
prompt = "Translate 'hello world' to Thai. Output only the translation."

# Warmup — first generate() pays the compile / cache cost.
generate(model, tokenizer, prompt=prompt, max_tokens=16, verbose=False)

n = 64
start = time.perf_counter()
generate(model, tokenizer, prompt=prompt, max_tokens=n, verbose=False)
elapsed = time.perf_counter() - start

tok_per_sec = n / elapsed if elapsed > 0 else 0.0
print(f"SPEED:{tok_per_sec:.1f} tok/s", flush=True)
del model
"#;
    let script = script.replace("REPO", &serde_json::Value::String(repo.to_string()).to_string());
    run_speed_script(&script).await
}

/// Run an MLX-Whisper transcription benchmark. Transcribes 1 second of
/// silence twice (warmup + timed), reports the realtime factor as
/// `"<n>× realtime"` (e.g. `"4.8× realtime"` means it can transcribe
/// 4.8 seconds of audio per second of wall time).
pub async fn benchmark_whisper_model(repo: &str) -> Result<String> {
    let script = r#"
import sys, time
import numpy as np
import mlx_whisper

# 1 second of silence at 16 kHz mono.
audio = np.zeros(16000, dtype=np.float32)

# Warmup — first call loads the model.
_ = mlx_whisper.transcribe(audio, path_or_hf_repo="REPO")

start = time.perf_counter()
_ = mlx_whisper.transcribe(audio, path_or_hf_repo="REPO")
elapsed = time.perf_counter() - start

realtime = 1.0 / elapsed if elapsed > 0 else 0.0
print(f"SPEED:{realtime:.1f}× realtime", flush=True)
"#;
    let script = script.replace("REPO", &serde_json::Value::String(repo.to_string()).to_string());
    run_speed_script(&script).await
}

/// Spawn `python -c <script>` with the project's venv interpreter,
/// capture stdout, find the `SPEED:...` line, return it.
async fn run_speed_script(script: &str) -> Result<String> {
    let py = super::mlx::python_path().ok_or_else(|| anyhow!("venv python not found"))?;
    let mut cmd = Command::new(py);
    cmd.arg("-c")
        .arg(script)
        .env("PYTHONUNBUFFERED", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // If the calling task is dropped, kill the python child.
    cmd.kill_on_drop(true);

    let mut child = cmd.spawn()?;
    let stderr = child.stderr.take();
    let mut stdout = child.stdout.take();

    // Drain stderr in the background so failure messages aren't lost.
    let stderr_task = tokio::spawn(async move {
        if let Some(mut s) = stderr {
            let mut buf = Vec::with_capacity(4096);
            let _ = s.read_to_end(&mut buf).await;
            let text = String::from_utf8_lossy(&buf);
            for line in text.lines() {
                if !line.is_empty() {
                    log::warn!("[benchmark stderr] {line}");
                }
            }
        }
    });

    // Read stdout fully — small (a few lines) so buffering is fine.
    let mut out_buf = Vec::with_capacity(4096);
    if let Some(mut s) = stdout.take() {
        let _ = s.read_to_end(&mut out_buf).await;
    }
    let out_text = String::from_utf8_lossy(&out_buf).to_string();

    let status = child.wait().await?;
    let _ = stderr_task.await;

    if !status.success() {
        return Err(anyhow!(
            "benchmark failed (exit code {:?}); last stdout: {}",
            status.code(),
            truncate(&out_text, 200)
        ));
    }

    parse_speed_line(&out_text).ok_or_else(|| {
        anyhow!(
            "benchmark produced no SPEED line. stdout was: {}",
            truncate(&out_text, 400)
        )
    })
}

/// Find the most recent `SPEED:<value> <unit>` line. The benchmark
/// scripts always print exactly one such line on success.
fn parse_speed_line(s: &str) -> Option<String> {
    for line in s.lines().rev() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("SPEED:") {
            return Some(rest.trim().to_string());
        }
    }
    None
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_speed_line() {
        assert_eq!(
            parse_speed_line("loading…\nSPEED:32.4 tok/s\n"),
            Some("32.4 tok/s".into())
        );
        assert_eq!(
            parse_speed_line("SPEED:4.8× realtime\n"),
            Some("4.8× realtime".into())
        );
        assert_eq!(parse_speed_line("nothing here"), None);
    }
}
