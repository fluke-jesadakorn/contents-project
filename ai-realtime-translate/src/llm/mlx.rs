//! MLX-LM bridge — invokes the project's .venv Python with `mlx_lm.load` +
//! `mlx_lm.generate` over stdin/stdout. This is the highest-quality path on
//! Apple Silicon — the model lives entirely in unified memory and runs on
//! the ANE/GPU via Apple's MLX framework.
//!
//! # Wire format
//!
//! * `model` is the full HuggingFace repo id, e.g. `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit`.
//!   We pass it straight to `mlx_lm.load(path_or_hf_repo=...)`. The first
//!   call downloads the model into `~/.cache/huggingface/`.
//! * stdin: a JSON payload `{"text": "...", "system": "...", "memory": "..."}`.
//! * stdout: the model's reply, trimmed.

use anyhow::{anyhow, Result};
use once_cell::sync::Lazy;
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

static VENV_PY: Lazy<Option<PathBuf>> = Lazy::new(|| {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for ancestor in manifest.ancestors() {
        let cand = ancestor.join(".venv/bin/python");
        if cand.exists() {
            return Some(cand);
        }
    }
    None
});

pub fn available() -> bool {
    VENV_PY.is_some()
}

/// Path to the project's venv Python, if found.
pub fn python_path() -> Option<&'static PathBuf> {
    VENV_PY.as_ref()
}

/// Translate `text` from `src_lang` to `tgt_lang` using the MLX model at the
/// given HuggingFace repo id (e.g. `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit`).
/// `system` is the full system prompt; `memory` is the optional recent-context
/// block.
pub async fn translate(
    text: &str,
    hf_repo: &str,
    system: &str,
    memory: Option<&str>,
) -> Result<String> {
    let py = VENV_PY
        .as_ref()
        .ok_or_else(|| anyhow!("venv python not found"))?;

    if hf_repo.trim().is_empty() {
        return Err(anyhow!("no model selected"));
    }

    // The Python script is a self-contained module — it loads the model,
    // formats the prompt with the chat template, and prints the reply.
    // We embed the values via Python's json module (safer than rolling
    // our own escaper for strings that may contain quotes / newlines).
    let script = r#"
import sys, json
from mlx_lm import load, generate

payload = json.loads(sys.stdin.read())
text = payload["text"]
system = payload.get("system") or ""
memory = payload.get("memory") or ""

model, tokenizer = load(REPO)

prompt = (
    f"<|im_start|>system\n{system}<|im_end|>\n"
    f"<|im_start|>user\n{memory}{text}<|im_end|>\n"
    f"<|im_start|>assistant\n"
)
resp = generate(
    model,
    tokenizer,
    prompt=prompt,
    max_tokens=512,
    temp=0.0,
    verbose=False,
)
print(resp)
"#;

    let script = script.replace("REPO", &json_string(hf_repo));

    let payload = serde_json::json!({
        "text": text,
        "system": system,
        "memory": memory.unwrap_or(""),
    });
    let payload_bytes = serde_json::to_vec(&payload)?;

    let mut cmd = Command::new(py);
    cmd.arg("-c").arg(&script);
    cmd.stdin(Stdio::piped());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());
    cmd.kill_on_drop(true);

    let mut child = cmd.spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(&payload_bytes).await?;
        drop(stdin);
    }
    let out = child.wait_with_output().await?;
    if !out.status.success() {
        return Err(anyhow!(
            "mlx_lm failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    let resp = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if resp.is_empty() {
        return Err(anyhow!("mlx_lm returned empty response"));
    }
    Ok(resp)
}

fn json_string(s: &str) -> String {
    serde_json::Value::String(s.to_string()).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_string_escapes() {
        let s = json_string("mlx-community/gemma-3-9b-it-4bit");
        assert_eq!(s, "\"mlx-community/gemma-3-9b-it-4bit\"");
        let s = json_string("a\"b");
        assert_eq!(s, "\"a\\\"b\"");
    }
}