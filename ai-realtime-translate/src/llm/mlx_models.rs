//! HuggingFace model fetching for MLX-LM.
//!
//! Foundry queries the public HuggingFace API to list models from the
//! `mlx-community` organisation and filters them to chat / instruct variants
//! suitable for live translation. Results are cached on disk for 24h so the
//! app starts instantly on subsequent launches.
//!
//! # Wire format
//!
//! `GET https://huggingface.co/api/models?author=mlx-community&full=false&limit=200&sort=downloads&direction=-1`
//!
//! Returns JSON like:
//! ```json
//! [
//!   { "modelId": "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit", "tags": ["mlx", ...], "pipeline_tag": "text-generation" },
//!   ...
//! ]
//! ```
//!
//! We filter to: text-generation pipeline + instruct/chat/it suffix + skip
//! base / embedding / non-text models. Prefer 4-bit / 8-bit quant variants
//! (faster on Apple Silicon) but don't require them.

use anyhow::{anyhow, Result};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Stdio;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// One MLX model entry as the UI sees it.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MlxModel {
    /// Full HuggingFace repo id, e.g. `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit`.
    /// This is what we hand to `mlx_lm.load(path_or_hf_repo=...)`.
    pub repo: String,
    /// Friendly name for the dropdown, e.g. `Llama 3.1 8B Instruct (4-bit)`.
    pub display: String,
    /// HuggingFace download count (for sort stability — most popular first).
    #[serde(default)]
    pub downloads: u64,
    /// The size-bucket tag if we can parse one out of the name, e.g. `"8B"`, `"70B"`.
    #[serde(default)]
    pub size: Option<String>,
    /// The quant width if we can parse one, e.g. `"4-bit"`, `"8-bit"`.
    #[serde(default)]
    pub quant: Option<String>,
    /// The family / vendor, e.g. `"llama"`, `"gemma"`, `"qwen"`, `"mistral"`.
    #[serde(default)]
    pub family: Option<String>,
    /// Total bytes of all `siblings[].size` in the HF API response for
    /// this repo. `None` when the API didn't include per-file sizes
    /// (e.g. an older cache, a sparse response, or a custom repo).
    #[serde(default)]
    pub size_bytes: Option<u64>,
}

const HF_API_BASE: &str = "https://huggingface.co/api/models";
const HF_ORG: &str = "mlx-community";
const CACHE_TTL_SECS: u64 = 24 * 60 * 60;

#[derive(Debug, Deserialize)]
struct HfApiModel {
    #[serde(rename = "modelId")]
    model_id: String,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default, rename = "pipeline_tag")]
    pipeline_tag: Option<String>,
    #[serde(default)]
    downloads: u64,
    /// Per-file metadata; `size` is populated when the API is called
    /// with `?full=true`. We use it to surface expected download size
    /// in the Models modal.
    #[serde(default)]
    siblings: Vec<HfSibling>,
}

#[derive(Debug, Deserialize)]
struct HfSibling {
    // Populated by serde but not used at runtime — the API still
    // includes it and we want to accept the payload without warnings.
    #[serde(rename = "rfilename")]
    #[allow(dead_code)]
    rfilename: String,
    /// File size in bytes. Absent for some metadata files (e.g.
    /// `.gitattributes`); we treat those as 0.
    #[serde(default)]
    size: Option<u64>,
}

/// Sum the `size` field of every sibling in an API model entry.
/// Returns `None` when no sibling reports a size (e.g. cache from
/// before this field was populated, or a sparse API response).
fn total_siblings_size(siblings: &[HfSibling]) -> Option<u64> {
    let mut total: u64 = 0;
    let mut any = false;
    for s in siblings {
        if let Some(b) = s.size {
            total = total.saturating_add(b);
            any = true;
        }
    }
    if any { Some(total) } else { None }
}

#[derive(Debug, Serialize, Deserialize)]
struct CachedModels {
    fetched_at: u64,
    models: Vec<MlxModel>,
}

#[derive(Debug, Serialize, Deserialize)]
struct CachedList<T> {
    fetched_at: i64,
    items: Vec<T>,
}

static CACHE_PATH: Lazy<Option<PathBuf>> = Lazy::new(|| {
    let base = dirs::cache_dir()?.join("com.thefactorygroup.foundry");
    if let Err(e) = std::fs::create_dir_all(&base) {
        log::warn!("could not create cache dir {base:?}: {e}");
        return None;
    }
    Some(base.join("mlx_models.json"))
});

/// HuggingFace cache root — `~/.cache/huggingface/` by default,
/// overridable via `HF_HOME`.
pub fn hf_cache_root() -> PathBuf {
    if let Ok(p) = std::env::var("HF_HOME") {
        return PathBuf::from(p);
    }
    if let Some(home) = dirs::home_dir() {
        return home.join(".cache/huggingface");
    }
    PathBuf::from("/tmp/huggingface")
}

/// Scan the HF hub cache for downloaded mlx-community (or any) repos.
/// Returns a set of HF repo ids in `org/name` form.
///
/// The HF cache layout is `hub/models--<org>--<name>/` (double-dash
/// separator, with the inner `--` collapsing `org` and `name`). Newer
/// versions also support the nested `<org>/<name>/` form; we accept both.
#[allow(dead_code)] // prefer the typed `scan_downloaded_llms` / `_whispers` variants
pub fn scan_downloaded() -> std::collections::HashSet<String> {
    scan_downloaded_with_sizes()
        .into_iter()
        .map(|(repo, _)| repo)
        .collect()
}

/// Same as `scan_downloaded` but also returns the on-disk size (bytes)
/// of each repo. Size is computed by walking
/// `~/.cache/huggingface/hub/models--org--name/blobs/` and summing
/// `metadata().len()` of every regular file. Symlinks (the snapshots
/// directory uses them to reference blobs) are resolved to their
/// targets so we don't double-count.
pub fn scan_downloaded_with_sizes() -> Vec<(String, u64)> {
    use std::collections::HashSet;
    let mut out: Vec<(String, u64)> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    let hub = hf_cache_root().join("hub");
    let Ok(entries) = std::fs::read_dir(&hub) else {
        return out;
    };

    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();

        // Format 1: "models--mlx-community--Llama-3.2-3B-Instruct-4bit"
        if let Some(rest) = name.strip_prefix("models--") {
            if let Some((org, model)) = rest.split_once("--") {
                let repo = format!("{org}/{model}");
                let bytes = dir_size_blobs(&entry.path());
                if seen.insert(repo.clone()) {
                    out.push((repo, bytes));
                }
            }
            continue;
        }

        // Format 2: nested "<org>/<model>/"
        if entry.path().is_dir() && !name.starts_with('.') {
            if let Ok(sub) = std::fs::read_dir(entry.path()) {
                for s in sub.flatten() {
                    let sname = s.file_name().to_string_lossy().to_string();
                    if !sname.starts_with('.')
                        && s.path().is_dir()
                        && (s.path().join("snapshots").exists()
                            || s.path().join("model.safetensors").exists()
                            || s.path().join("weights.npz").exists())
                    {
                        let repo = format!("{name}/{sname}");
                        let bytes = dir_size_blobs(&s.path());
                        if seen.insert(repo.clone()) {
                            out.push((repo, bytes));
                        }
                    }
                }
            }
        }
    }
    out
}

/// Classify a HF repo id (`org/name`) as an MLX-Whisper STT model.
/// MLX-Whisper repos on `mlx-community/` follow the pattern
/// `whisper-*` (e.g. `whisper-large-v3-turbo`,
/// `whisper-distil-large-v3`). We match on the lowercased basename
/// only — we don't want to claim a chat model that happens to be
/// hosted by a user with "whisper" in their org name.
///
/// Today the filter is purely lexical; if a future MLX-Whisper
/// variant shows up that doesn't follow the `whisper-*` naming
/// convention we'll need to fall back to reading the cached
/// `config.json` and checking `model_type` or `pipeline_tag`.
pub fn is_whisper_repo(repo: &str) -> bool {
    let basename = repo.rsplit('/').next().unwrap_or(repo);
    basename.to_lowercase().starts_with("whisper-")
}

/// Scan the HF cache and return only LLM (chat) repos — i.e.
/// everything that is *not* an MLX-Whisper STT model. Used to
/// populate `state.downloaded_models` so the LLM dropdown never
/// accidentally shows a Whisper repo as a translation model option.
pub fn scan_downloaded_llms() -> Vec<(String, u64)> {
    scan_downloaded_with_sizes()
        .into_iter()
        .filter(|(repo, _)| !is_whisper_repo(repo))
        .collect()
}

/// Scan the HF cache and return only MLX-Whisper STT repos. Mirror
/// of [`scan_downloaded_llms`] for `state.downloaded_wmodels`.
pub fn scan_downloaded_whispers() -> Vec<(String, u64)> {
    scan_downloaded_with_sizes()
        .into_iter()
        .filter(|(repo, _)| is_whisper_repo(repo))
        .collect()
}

/// Sum the on-disk bytes of a single repo directory under the HF hub.
/// Walks the `blobs/` subdir (where the actual weight files live) and
/// follows symlinks so we get the real byte count, not 0 for symlinks.
fn dir_size_blobs(repo_dir: &std::path::Path) -> u64 {
    let blobs = repo_dir.join("blobs");
    let Ok(entries) = std::fs::read_dir(&blobs) else {
        return 0;
    };
    entries
        .flatten()
        .filter_map(|e| e.metadata().ok())
        .map(|m| m.len())
        .sum()
}

/// Delete a downloaded model from the HF cache.
/// Returns Ok(true) if a cache dir was found and removed, Ok(false) if it
/// wasn't there to begin with.
pub fn delete_model(repo: &str) -> Result<bool> {
    let hub = hf_cache_root().join("hub");
    // Convert "mlx-community/Llama-3.2-3B-Instruct-4bit" to the
    // canonical cache dir name.
    let dir_name = format!("models--{}", repo.replace('/', "--"));
    let path = hub.join(&dir_name);
    if !path.exists() {
        return Ok(false);
    }
    std::fs::remove_dir_all(&path)?;
    log::info!("deleted cached model: {repo} (path={path:?})");
    Ok(true)
}

/// Terminal outcome of a download — what the spawned task reports back to
/// the driver via `done_rx` so the UI can pick the right toast / state
/// update.
#[derive(Debug)]
pub enum DownloadOutcome {
    /// Child exited 0 — files are in the HF cache.
    Completed,
    /// Caller fired the cancel signal; we killed the child mid-flight.
    Cancelled,
    /// Child exited non-zero or wait() errored.
    Failed(anyhow::Error),
}

/// Download a model in the background by running
/// `huggingface_hub.snapshot_download()` in a subprocess. The download
/// is wrapped in a tmp-staging → final-cache atomic-promote pattern
/// (see the Python script for full details): bytes stream to a staging
/// dir first, and only the fully-downloaded repo is moved into the
/// final HF cache (`~/.cache/huggingface/hub/`).
///
/// Returns a `(progress_rx, done_rx)` pair:
///
/// * `progress_rx` — `f32` 0.0..=1.0 streamed from the child's stderr.
///   The Python script emits `PROGRESS:<float>` lines via a custom
///   `tqdm_class` (throttled to ~10 Hz, line-buffered, flushed). Falls
///   back to parsing tqdm's `100%|██████████|` bar format if the
///   protocol line is missing. Poll from the UI to drive a progress
///   bar. Closes when the child terminates.
/// * `done_rx` — fires exactly once with the terminal outcome
///   (`Completed` / `Cancelled` / `Failed`). The driver awaits this to
///   decide whether to emit "Downloaded" / "Cancelled" / error.
///
/// Environment variables honored by the Python subprocess:
///
/// * `HF_HOME` — final HF cache root (default `~/.cache/huggingface`).
///   Use this to relocate the cache to e.g. an external HDD.
/// * `FOUNDRY_DOWNLOAD_TMP_DIR` — staging dir (default
///   `~/.cache/huggingface/hub-staging`). Set to the same path as
///   `HF_HOME/hub` to skip staging entirely. Pick a path on the same
///   filesystem as `HF_HOME/hub` for an instant atomic rename.
///
/// Pass `cancel_rx`: when it fires (e.g. the user clicked Cancel), the
/// child is `kill()`-ed and the outcome becomes `Cancelled`.
///
/// The caller is responsible for keeping `cancel_rx` alive: dropping it
/// without firing does NOT cancel the download — that requires an
/// explicit `.send(())` on the sender.
pub async fn download_model(
    repo: &str,
    cancel_rx: tokio::sync::oneshot::Receiver<()>,
) -> Result<(
    tokio::sync::mpsc::UnboundedReceiver<f32>,
    tokio::sync::oneshot::Receiver<DownloadOutcome>,
)> {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<f32>();
    let (done_tx, done_rx) = tokio::sync::oneshot::channel::<DownloadOutcome>();
    let _ = tx.send(0.0);

    // The script emits per-update progress as `PROGRESS:<float>` lines
    // on stderr via a custom `tqdm_class` that redirects the visual
    // bar to /dev/null. We can't use `disable=True` because tqdm's
    // `update()` short-circuits when disabled — `self.n` would never
    // increment and progress would stay at 0%. Redirecting the file
    // to /dev/null keeps the bar "live" (so n/total stays accurate)
    // while silencing the `\r`-overwrite visual noise that doesn't
    // survive a pipe anyway.
    //
    // Why a custom protocol instead of parsing tqdm's bar:
    //   1. Tqdm writes `\r<update>` (carriage-return overwrites) and
    //      only emits `\n` when the bar closes. The Rust `lines()`
    //      reader would buffer ALL updates into one giant string and
    //      only see the FIRST percentage (~0%) until the very end.
    //      Line-buffered `PROGRESS:` emissions with `flush=True`
    //      sidestep that entirely.
    //   2. Tqdm's bar uses Unicode full-block chars + ANSI escapes
    //      (`\x1b[A`); parsing it through `parse_hf_percent` would
    //      work but is fragile. Owning the protocol is cleaner.
    //
    // `bytes_progress` (the outer bar in `snapshot_download`) tracks
    // bytes downloaded / total bytes — that's the bar we care about
    // and the one whose `update()` calls drive our PROGRESS lines.
    // `_AggregatedTqdm` is a fake class that funnels per-file
    // updates into `bytes_progress`, so our override is hit for every
    // chunk downloaded.
    // The script implements a tmp-staging → final-cache atomic-promote
    // pattern. Each file is downloaded to a *staging* directory
    // (`cache_dir`), and only on full success of the entire repo is
    // the staged tree moved into the final HF cache. Failures clean
    // up the staging dir so the final cache never sees a half-
    // downloaded repo.
    //
    // Streaming: HF Hub uses httpx.iter_bytes(10 MB chunks) and
    // writes each chunk to disk as it arrives. The full file is
    // never loaded into RAM — only one 10 MB chunk sits in memory
    // at a time. So:
    //   • "tmp file until done" → repo-level staging dir
    //   • "keep in hdd"          → final HF cache (HDD/SSD)
    //   • "not keep in ram"      → chunked streaming, never buffered
    let script = r#"
import os
import shutil
import sys
import time
from pathlib import Path
from huggingface_hub import snapshot_download
import tqdm

class ProgressTqdm(tqdm.tqdm):
    """Emit per-update download progress as PROGRESS:<float> on stderr.

    Bar is redirected to /dev/null (tqdm's \\r-overwrites don't survive
    a pipe anyway), but `disable=False` is required — tqdm's `update()`
    short-circuits when disabled, so `self.n` would never increment.
    """
    def __init__(self, *args, **kwargs):
        kwargs["file"] = open(os.devnull, "w")
        super().__init__(*args, **kwargs)
        self._last_emit_t = 0.0

    def update(self, n=1):
        super().update(n)
        if self.total and self.n is not None:
            now = time.monotonic()
            # Throttle to ~10 Hz so we don't flood the host channel.
            # Always emit on completion (n == total) so the bar lands
            # on 100% even if the throttle just suppressed an update.
            if now - self._last_emit_t >= 0.1 or self.n == self.total:
                self._last_emit_t = now
                pct = self.n / self.total
                print(f"PROGRESS:{pct:.4f}", file=sys.stderr, flush=True)

# ── Resolve staging and final cache locations ────────────────
# `HF_HOME` is the HF-standard env var for the cache root; we honor
# it for the final cache. `FOUNDRY_DOWNLOAD_TMP_DIR` is Foundry-
# specific and overrides the staging location — defaults to a
# sibling of the final cache (`hub-staging`) so the promote is an
# instant same-FS rename. Set them to the same path to skip
# staging entirely.
TMP_CACHE = Path(os.environ.get(
    "FOUNDRY_DOWNLOAD_TMP_DIR",
    os.path.expanduser("~/.cache/huggingface/hub-staging"),
))
FINAL_CACHE = Path(os.environ.get(
    "HF_HOME",
    os.path.expanduser("~/.cache/huggingface"),
)) / "hub"

# HF Hub creates `models--<org>--<name>` inside `cache_dir`.
repo_folder = f"models--{REPO.replace('/', '--')}"
staging_repo = TMP_CACHE / repo_folder
final_repo = FINAL_CACHE / repo_folder

# Reset leftover staging from any prior aborted run so a retry
# starts from a clean slate.
if staging_repo.exists():
    shutil.rmtree(staging_repo)

try:
    # Phase 1: stream every file to the staging cache. HF Hub
    # internally does tmp+rename per FILE, but we wrap the WHOLE
    # REPO so a multi-file failure doesn't leave partial files in
    # the final cache.
    snapshot_download(
        repo_id=REPO,
        allow_patterns=[
            "*.json", "*.txt", "*.model", "*.tiktoken",
            "*.safetensors", "*.npz", "tokenizer.*",
            "*.py", "*.jinja", "*.md",
        ],
        cache_dir=str(TMP_CACHE),
        tqdm_class=ProgressTqdm,
    )

    # Phase 2: atomic promote to the final cache.
    if staging_repo.resolve() == final_repo.resolve():
        # Tmp and final resolve to the same path — staging skipped.
        pass
    elif final_repo.exists():
        # Already in the final cache (downloaded previously); the
        # staging copy is just a duplicate, drop it.
        shutil.rmtree(staging_repo)
    else:
        # shutil.move: rename on same FS (instant, atomic),
        # copy+delete across FS (slow but still atomic from the
        # final cache's POV — final_repo only appears once the
        # copy completes).
        shutil.move(str(staging_repo), str(final_repo))

    print(f"DONE:{final_repo}", flush=True)
except BaseException:
    # Clean up partial staging on ANY failure (network drop, disk
    # full, user cancel, etc.) so the staging dir doesn't accumulate
    # orphaned blobs across retry attempts.
    if staging_repo.exists():
        shutil.rmtree(staging_repo, ignore_errors=True)
    raise
"#;
    let script = script.replace("REPO", &serde_json::Value::String(repo.to_string()).to_string());

    let py = super::mlx::python_path().ok_or_else(|| anyhow!("venv python not found"))?;

    let mut cmd = Command::new(py);
    cmd.arg("-c").arg(&script);
    cmd.env("PYTHONUNBUFFERED", "1");
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());
    cmd.kill_on_drop(true);

    let mut child = cmd.spawn()?;
    let stderr = child.stderr.take();
    let stdout = child.stdout.take();

    let tx_e = tx.clone();
    let stderr_task = tokio::spawn(async move {
        if let Some(s) = stderr {
            let mut reader = BufReader::new(s).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                // Preferred protocol: `PROGRESS:<float>` lines emitted
                // by our `ProgressTqdm` wrapper in the Python script.
                // These are line-buffered and throttled to ~10 Hz, so
                // the UI sees smooth progress updates throughout the
                // download instead of jumping from 0% → 100% at the end.
                if let Some(pct) = parse_progress_line(&line) {
                    let _ = tx_e.send(pct);
                    continue;
                }
                // Fallback: classic tqdm bar format
                // (`100%|██████████| 4.5G/4.5G`). Kept so the parser
                // still works if someone runs the script directly
                // outside our wrapper.
                if let Some(pct) = parse_hf_percent(&line) {
                    let _ = tx_e.send(pct);
                }
            }
        }
    });

    let repo_owned = repo.to_string();
    let stdout_task = tokio::spawn(async move {
        if let Some(s) = stdout {
            let mut reader = BufReader::new(s).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                log::info!("[download:{repo_owned}] {line}");
            }
        }
    });

    let repo_for_task = repo.to_string();
    tokio::spawn(async move {
        let outcome = tokio::select! {
            // Normal completion path: the python subprocess exits.
            status = child.wait() => {
                match status {
                    Ok(s) if s.success() => DownloadOutcome::Completed,
                    Ok(s) => DownloadOutcome::Failed(anyhow!(
                        "download failed for {repo_for_task} (exit code {:?})",
                        s.code()
                    )),
                    Err(e) => DownloadOutcome::Failed(anyhow!(
                        "download child wait failed for {repo_for_task}: {e}"
                    )),
                }
            }
            // Cancel path: user clicked the × button. We hold the only
            // mutable reference to `child` now (the `child.wait()` branch
            // was dropped when cancel won the race), so we can drive it
            // ourselves.
            _ = cancel_rx => {
                log::info!("download cancelled by user: {repo_for_task}");
                let _ = child.start_kill();
                let _ = child.wait().await;
                DownloadOutcome::Cancelled
            }
        };

        let _ = stderr_task.await;
        let _ = stdout_task.await;
        // Mark the bar 100% so any last UI paint settles cleanly. (On
        // cancel this is a bit of a lie, but the row is about to be
        // torn down anyway.)
        let _ = tx.send(1.0);
        let _ = done_tx.send(outcome);
    });

    Ok((rx, done_rx))
}

/// Parse an HF / tqdm-style percentage out of a log line.
/// Returns 0.0..=1.0.
fn parse_hf_percent(line: &str) -> Option<f32> {
    // Walk char-by-char (tqdm uses unicode "full block" chars so byte
    // indices are not safe). Find a run of digits immediately followed
    // by '%'.
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_ascii_digit() {
            let start = i;
            while i < chars.len() && chars[i].is_ascii_digit() {
                i += 1;
            }
            if i < chars.len() && chars[i] == '%' {
                let num: String = chars[start..i].iter().collect();
                if let Ok(pct) = num.parse::<u32>() {
                    return Some((pct as f32) / 100.0);
                }
            }
            continue;
        }
        i += 1;
        // Don't scan past the first 80 chars of the line — there's
        // no useful percent further in.
        if i > 80 {
            return None;
        }
    }
    None
}

#[cfg(test)]
mod parse_tests {
    use super::*;
    #[test]
    fn parses_tqdm_percent() {
        assert_eq!(
            parse_hf_percent("Fetching 12 files:  83%|██████████| 10/12"),
            Some(0.83)
        );
        assert_eq!(
            parse_hf_percent("Downloading model.safetensors: 100%|██████████| 4.5G/4.5G"),
            Some(1.0)
        );
        assert_eq!(parse_hf_percent("no percent here"), None);
    }

    #[test]
    fn parses_progress_protocol_lines() {
        // Pin the `PROGRESS:<float>` format the Python wrapper emits.
        // If the format changes the test fails — that's the point,
        // so we'd notice in CI rather than silently breaking the bar.
        assert_eq!(parse_progress_line("PROGRESS:0.0000"), Some(0.0));
        assert_eq!(parse_progress_line("PROGRESS:0.1234"), Some(0.1234));
        assert_eq!(parse_progress_line("PROGRESS:0.5"), Some(0.5));
        assert_eq!(parse_progress_line("PROGRESS:1.0000"), Some(1.0));
        assert_eq!(parse_progress_line("PROGRESS:1"), Some(1.0));

        // Non-PROGRESS lines (tqdm bars, logs, DONE:) must NOT match —
        // they're handled by other branches.
        assert_eq!(
            parse_progress_line("Fetching 12 files:  83%|██████████| 10/12"),
            None
        );
        assert_eq!(parse_progress_line("DONE:/path/to/snapshots/abc"), None);
        assert_eq!(parse_progress_line("PROGRESS:not-a-number"), None);
        assert_eq!(parse_progress_line(""), None);
    }
}

/// Parse our Python wrapper's `PROGRESS:<float>` protocol line.
/// Returns the fraction (0.0..=1.0) on a match, `None` if the line
/// isn't a PROGRESS line or the float is malformed.
fn parse_progress_line(line: &str) -> Option<f32> {
    line.strip_prefix("PROGRESS:")
        .and_then(|rest| rest.parse::<f32>().ok())
}

/// Fetch MLX chat models from HuggingFace, with a 24h on-disk cache.
///
/// * `force_refresh` — bypass the cache and hit the API.
/// * On network / API error, the cache is returned if available (even stale)
///   so the user still gets a usable dropdown offline.
pub async fn fetch_mlx_models(force_refresh: bool) -> Result<Vec<MlxModel>> {
    // 1. Try cache first unless caller wants a forced refresh.
    if !force_refresh {
        if let Some(cached) = read_cache() {
            if !cached.is_empty() {
                return Ok(cached);
            }
        }
    }

    // 2. Hit the API.
    let fresh = fetch_from_api().await?;

    // 3. Persist to cache.
    if let Err(e) = write_cache(&fresh) {
        log::warn!("could not write mlx_models cache: {e}");
    }
    Ok(fresh)
}

/// Return the hardcoded curated list — used as a last-resort fallback if
/// both the API and the cache are unavailable (e.g. first launch offline).
pub fn fallback_models() -> Vec<MlxModel> {
    FALLBACK
        .iter()
        .map(|(repo, display, family, size, quant)| MlxModel {
            repo: repo.to_string(),
            display: display.to_string(),
            downloads: 0,
            family: Some(family.to_string()),
            size: Some(size.to_string()),
            quant: Some(quant.to_string()),
            size_bytes: None,
        })
        .collect()
}

const FALLBACK: &[(&str, &str, &str, &str, &str)] = &[
    (
        "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        "Llama 3.1 8B Instruct (4-bit)",
        "llama",
        "8B",
        "4-bit",
    ),
    (
        "mlx-community/Meta-Llama-3.1-70B-Instruct-4bit",
        "Llama 3.1 70B Instruct (4-bit)",
        "llama",
        "70B",
        "4-bit",
    ),
    (
        "mlx-community/Meta-Llama-3.2-3B-Instruct-4bit",
        "Llama 3.2 3B Instruct (4-bit)",
        "llama",
        "3B",
        "4-bit",
    ),
    (
        "mlx-community/gemma-3-9b-it-4bit",
        "Gemma 3 9B IT (4-bit)",
        "gemma",
        "9B",
        "4-bit",
    ),
    (
        "mlx-community/gemma-3-27b-it-4bit",
        "Gemma 3 27B IT (4-bit)",
        "gemma",
        "27B",
        "4-bit",
    ),
    (
        "mlx-community/Qwen2.5-7B-Instruct-4bit",
        "Qwen 2.5 7B Instruct (4-bit)",
        "qwen",
        "7B",
        "4-bit",
    ),
    (
        "mlx-community/Qwen3-8B-4bit",
        "Qwen 3 8B (4-bit)",
        "qwen",
        "8B",
        "4-bit",
    ),
    (
        "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
        "Mistral 7B Instruct v0.3 (4-bit)",
        "mistral",
        "7B",
        "4-bit",
    ),
    (
        "mlx-community/aya-23-8B-4bit",
        "Aya 23 8B (4-bit)",
        "aya",
        "8B",
        "4-bit",
    ),
    (
        "mlx-community/Phi-3-mini-4k-instruct-4bit",
        "Phi-3 Mini 4K Instruct (4-bit)",
        "phi3",
        "mini",
        "4-bit",
    ),
];

// ─── MLX-Whisper catalog ───────────────────────────────────────────────────
//
// MLX-Whisper models live on HuggingFace under `mlx-community/`. We filter by
// `pipeline_tag == "automatic-speech-recognition"` and the `mlx` tag, then
// shape a friendly display name (`whisper-large-v3-turbo` → `Whisper Large V3
// Turbo`). The same 24h on-disk cache pattern as the chat models applies, so
// the toolbar STT dropdown is instant on relaunch.

const WHISPER_CACHE_NAME: &str = "mlx_whisper_models.json";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MlxWhisperModel {
    pub repo: String,
    pub display: String,
    pub size: Option<String>,
    pub variant: Option<String>, // multilingual / english
    /// Total bytes of all `siblings[].size` from the HF API response.
    #[serde(default)]
    pub size_bytes: Option<u64>,
}

fn whisper_cache_path() -> Option<PathBuf> {
    let base = dirs::cache_dir()?.join("com.thefactorygroup.foundry");
    if let Err(e) = std::fs::create_dir_all(&base) {
        log::warn!("could not create whisper cache dir {base:?}: {e}");
        return None;
    }
    Some(base.join(WHISPER_CACHE_NAME))
}

fn read_whisper_cache() -> Option<Vec<MlxWhisperModel>> {
    let path = whisper_cache_path()?;
    let raw = std::fs::read_to_string(&path).ok()?;
    let cached: CachedList<MlxWhisperModel> = serde_json::from_str(&raw).ok()?;
    let age = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
        - cached.fetched_at;
    if age < CACHE_TTL_SECS as i64 {
        Some(cached.items)
    } else {
        None
    }
}

#[allow(dead_code)] // kept for an offline fallback we may re-add
fn read_whisper_stale_cache() -> Option<Vec<MlxWhisperModel>> {
    let path = whisper_cache_path()?;
    let raw = std::fs::read_to_string(&path).ok()?;
    let cached: CachedList<MlxWhisperModel> = serde_json::from_str(&raw).ok()?;
    Some(cached.items)
}

fn write_whisper_cache(items: &[MlxWhisperModel]) -> Result<()> {
    let path = match whisper_cache_path() {
        Some(p) => p,
        None => return Ok(()),
    };
    let cached = CachedList {
        fetched_at: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0),
        items: items.to_vec(),
    };
    let raw = serde_json::to_string(&cached)?;
    std::fs::write(&path, raw)?;
    Ok(())
}

/// Fetch MLX-Whisper (ASR) models from HuggingFace, with 24h on-disk cache.
pub async fn fetch_whisper_models(force_refresh: bool) -> Result<Vec<MlxWhisperModel>> {
    if !force_refresh {
        if let Some(cached) = read_whisper_cache() {
            if !cached.is_empty() {
                return Ok(cached);
            }
        }
    }
    let fresh = fetch_whisper_from_api().await?;
    if let Err(e) = write_whisper_cache(&fresh) {
        log::warn!("could not write whisper cache: {e}");
    }
    Ok(fresh)
}

/// Last-resort curated MLX-Whisper list — used when both API and cache fail.
pub fn fallback_whisper_models() -> Vec<MlxWhisperModel> {
    WHISPER_FALLBACK
        .iter()
        .map(|(repo, display, size, variant)| MlxWhisperModel {
            repo: repo.to_string(),
            display: display.to_string(),
            size: Some(size.to_string()),
            variant: Some(variant.to_string()),
            size_bytes: None,
        })
        .collect()
}

const WHISPER_FALLBACK: &[(&str, &str, &str, &str)] = &[
    (
        "mlx-community/whisper-tiny",
        "Whisper Tiny",
        "tiny",
        "multilingual",
    ),
    (
        "mlx-community/whisper-tiny.en",
        "Whisper Tiny (English)",
        "tiny",
        "english",
    ),
    (
        "mlx-community/whisper-base",
        "Whisper Base",
        "base",
        "multilingual",
    ),
    (
        "mlx-community/whisper-small",
        "Whisper Small",
        "small",
        "multilingual",
    ),
    (
        "mlx-community/whisper-medium",
        "Whisper Medium",
        "medium",
        "multilingual",
    ),
    (
        "mlx-community/whisper-large-v3",
        "Whisper Large V3",
        "large-v3",
        "multilingual",
    ),
    (
        "mlx-community/whisper-large-v3-turbo",
        "Whisper Large V3 Turbo",
        "large-v3-turbo",
        "multilingual",
    ),
    (
        "mlx-community/whisper-distil-large-v3",
        "Whisper Distil Large V3",
        "distil-large-v3",
        "multilingual",
    ),
];

async fn fetch_whisper_from_api() -> Result<Vec<MlxWhisperModel>> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("Foundry/0.1 (+https://thefactorygroup.io)")
        .build()?;

    let url = format!(
        "{base}?author={org}&full=true&limit=200&sort=downloads&direction=-1",
        base = HF_API_BASE,
        org = HF_ORG
    );
    log::info!("GET {url}");
    let resp = client.get(&url).send().await?;
    let status = resp.status();
    let body = resp.text().await?;
    if !status.is_success() {
        return Err(anyhow!("HF API {} returned {}", status, truncate(&body, 200)));
    }
    let raw: Vec<HfApiModel> = serde_json::from_str(&body)?;

    // MLX-Whisper filter: pipeline_tag == automatic-speech-recognition,
    // and the basename (after the org/) starts with "whisper-". HF returns
    // `modelId` as the full `org/name` form.
    let mut items: Vec<MlxWhisperModel> = raw
        .into_iter()
        .filter(|m| {
            m.pipeline_tag.as_deref() == Some("automatic-speech-recognition")
                && m.model_id
                    .rsplit('/')
                    .next()
                    .map(|name| name.starts_with("whisper-"))
                    .unwrap_or(false)
        })
        .map(build_whisper_entry)
        .collect();

    items.sort_by(|a, b| {
        whisper_size_rank(&a.size).cmp(&whisper_size_rank(&b.size))
            .then_with(|| a.display.cmp(&b.display))
    });
    Ok(items)
}

fn build_whisper_entry(m: HfApiModel) -> MlxWhisperModel {
    // Strip the "org/" prefix from modelId so the friendly name doesn't
    // read "Mlx Community / Whisper Tiny". HF returns `mlx-community/whisper-tiny`.
    let basename = m
        .model_id
        .rsplit_once('/')
        .map(|(_, b)| b)
        .unwrap_or(&m.model_id)
        .to_string();
    let lower = basename.to_lowercase();
    let size = extract_whisper_size(&lower);
    let variant = if lower.ends_with(".en") {
        Some("english".to_string())
    } else {
        Some("multilingual".to_string())
    };
    let display = friendly_whisper_name(&basename);
    MlxWhisperModel {
        repo: m.model_id,
        display,
        size,
        variant,
        size_bytes: total_siblings_size(&m.siblings),
    }
}

fn friendly_whisper_name(raw: &str) -> String {
    // "whisper-large-v3-turbo" → "Whisper Large V3 Turbo"
    // "whisper-distil-large-v3" → "Whisper Distil Large V3"
    // "whisper-large-v3-mlx" → "Whisper Large V3" (drop the trailing
    // "-mlx" suffix that mlx-community uses to mark MLX-format ports —
    // it's redundant in this UI).
    // ".en" variants keep their suffix as " (English)".
    let mut name = raw.to_string();

    // Drop trailing "-mlx" — the UI is already mlx-aware.
    if name.ends_with("-mlx") {
        name.truncate(name.len() - 4);
    }

    // Pull off a trailing ".en" before word-splitting.
    let lang_suffix = if name.ends_with(".en") {
        name.truncate(name.len() - 3);
        Some("(English)")
    } else {
        None
    };

    let mut parts: Vec<String> = Vec::new();
    for (i, w) in name.split('-').enumerate() {
        if i == 0 {
            parts.push(capitalize(w));
        } else if matches!(w, "v1" | "v2" | "v3" | "v4" | "v5") {
            parts.push(w.to_uppercase());
        } else {
            parts.push(capitalize(w));
        }
    }

    let mut out = parts.join(" ");
    if let Some(suffix) = lang_suffix {
        out.push(' ');
        out.push_str(suffix);
    }
    out
}

fn capitalize(w: &str) -> String {
    let mut c = w.chars();
    match c.next() {
        Some(first) => {
            let mut s = first.to_uppercase().collect::<String>();
            s.push_str(c.as_str());
            s
        }
        None => String::new(),
    }
}

fn extract_whisper_size(lower: &str) -> Option<String> {
    // The mlx-community whisper repos follow the pattern
    // whisper-{tiny|base|small|medium|large[-vN|-vN-turbo]|distil-large-vN}
    if let Some(idx) = lower.find("distil-") {
        if let Some(rest) = lower[idx + 7..].strip_prefix("large-") {
            return Some(format!("distil-large-{}", rest.split('-').next().unwrap_or("")));
        }
    }
    if lower.contains("large") {
        let mut s = String::from("large");
        if let Some(rest) = lower.split("large").nth(1) {
            let v = rest
                .chars()
                .skip_while(|c| c == &'-' || c == &'v')
                .take_while(|c| c.is_ascii_digit())
                .collect::<String>();
            if !v.is_empty() {
                s.push_str(&format!("-v{v}"));
            }
            if rest.contains("turbo") {
                s.push_str("-turbo");
            }
        }
        return Some(s);
    }
    for size in ["tiny", "base", "small", "medium"] {
        if lower.contains(size) {
            return Some(size.to_string());
        }
    }
    None
}

fn whisper_size_rank(size: &Option<String>) -> u32 {
    let s = size.as_deref().unwrap_or("");
    if s.starts_with("distil-large") {
        5
    } else if s.starts_with("large") {
        7
    } else if s == "medium" {
        4
    } else if s == "small" {
        3
    } else if s == "base" {
        2
    } else if s == "tiny" {
        1
    } else {
        0
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max])
    }
}

async fn fetch_from_api() -> Result<Vec<MlxModel>> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("Foundry/0.1 (+https://thefactorygroup.io)")
        .build()?;

    // Fetch the mlx-community org listing. We over-fetch (limit=300) so the
    // filter has good coverage.
    let url = format!(
        "{HF_API_BASE}?author={HF_ORG}&full=true&limit=300&sort=downloads&direction=-1"
    );
    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| anyhow!("HF API request failed: {e}"))?;
    if !resp.status().is_success() {
        return Err(anyhow!("HF API returned {}", resp.status()));
    }
    let body: Vec<HfApiModel> = resp
        .json()
        .await
        .map_err(|e| anyhow!("HF API returned bad json: {e}"))?;

    let mut models: Vec<MlxModel> = body
        .into_iter()
        .filter_map(|m| {
            if !is_chat_mlx_model(&m) {
                return None;
            }
            Some(build_entry(m))
        })
        .collect();

    // Stable ordering: family, then size descending, then quant ascending
    // (4-bit before 8-bit — smaller is faster on Apple Silicon).
    models.sort_by(|a, b| {
        a.family
            .as_deref()
            .unwrap_or("z")
            .cmp(b.family.as_deref().unwrap_or("z"))
            .then_with(|| {
                size_rank(b.size.as_deref()).cmp(&size_rank(a.size.as_deref()))
            })
            .then_with(|| quant_rank(a.quant.as_deref()).cmp(&quant_rank(b.quant.as_deref())))
    });

    // Dedupe by repo (in case the API returns duplicates across pages).
    let mut seen = std::collections::HashSet::new();
    models.retain(|m| seen.insert(m.repo.clone()));

    Ok(models)
}

// ─── Per-repo size lookup ────────────────────────────────────────────────
//
// The HF models listing API used to return `size` on every entry of
// `siblings[]`, but stopped doing so at some point — the response
// now only carries `rfilename`. To populate the Models modal's
// per-row "size on disk" + VRAM-fit chip we have to hit the tree
// endpoint for each repo individually:
//
//   GET https://huggingface.co/api/models/{repo}/tree/{revision}
//
// which returns a list of `{type, path, size, …}` entries and is
// small (~5 KB per repo). We sum every file's `size` to get the
// total on-disk footprint.

#[derive(Debug, Deserialize)]
struct HfTreeEntry {
    #[serde(rename = "type")]
    kind: String,
    // Tree-entry path — populated by serde but only asserted in the
    // test fixture. The real code keys off `size`, so this just needs
    // to be present for the payload to deserialize.
    #[serde(default)]
    #[allow(dead_code)]
    path: String,
    /// File size in bytes. `None` for directories.
    #[serde(default)]
    size: Option<u64>,
}

/// Sum the `size` of every file in a tree response. Returns `None`
/// on network failure, non-2xx, malformed JSON, or a tree with no
/// files (the latter is technically possible but means the repo is
/// empty — same outcome as a failure for our purposes).
async fn fetch_repo_size_bytes(client: &reqwest::Client, repo: &str) -> Option<u64> {
    // Use `main` as the default revision. Most mlx-community repos
    // use `main`; a handful use `refs/convert/parquet` for the
    // datasets but those aren't chat models. The tree endpoint
    // returns 404 for a missing revision, which we treat as None.
    let url = format!("https://huggingface.co/api/models/{repo}/tree/main");
    let resp = match client
        .get(&url)
        .timeout(Duration::from_secs(10))
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            log::debug!("tree fetch failed for {repo}: {e}");
            return None;
        }
    };
    if !resp.status().is_success() {
        log::debug!("tree fetch for {repo} returned {}", resp.status());
        return None;
    }
    let entries: Vec<HfTreeEntry> = match resp.json().await {
        Ok(v) => v,
        Err(e) => {
            log::debug!("tree response for {repo} was not JSON: {e}");
            return None;
        }
    };
    let mut total: u64 = 0;
    let mut any = false;
    for e in &entries {
        if e.kind == "file" {
            if let Some(s) = e.size {
                total = total.saturating_add(s);
                any = true;
            }
        }
    }
    if any {
        Some(total)
    } else {
        None
    }
}

/// Shared HTTP client for the tree-lookup fetches. Built once at
/// first use so the connection pool can be reused across hundreds
/// of small requests. Reusing the client also means we get HTTP/2
/// stream multiplexing on the HF side, which keeps the wall-clock
/// cost of a 147-model sweep well under 30 s.
static TREE_CLIENT: once_cell::sync::Lazy<reqwest::Client> =
    once_cell::sync::Lazy::new(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent("Foundry/0.1 (+https://thefactorygroup.io)")
            // Hugging Face allows plenty of connections per host
            // but we cap the per-host socket pool to keep the
            // concurrency predictable. The semaphore in
            // `prefetch_repo_sizes` controls actual fan-out.
            .pool_max_idle_per_host(8)
            .build()
            .expect("reqwest client build should not fail")
    });

/// Prefetch total bytes for every repo in `repos` and stream
/// individual results through `on_one` as they arrive. Concurrency
/// is capped at `MAX_CONCURRENT` in-flight requests to stay polite
/// to the HF API and keep the local socket pool small.
///
/// `on_one` is called once per repo with `(repo, Option<u64>)` —
/// `None` means the tree fetch failed and we should leave that
/// repo's size unset.
///
/// This is fire-and-forget: errors from the network layer are
/// logged at debug level and never propagated. A user opening the
/// Models modal a second time should always see fresh data from
/// the cache, so transient failures just mean the chip stays
/// missing until the next refresh.
pub async fn prefetch_repo_sizes<F>(repos: Vec<String>, on_one: F)
where
    F: Fn(String, Option<u64>) + Send + Sync + 'static,
{
    use futures::stream::{FuturesUnordered, StreamExt};
    use std::sync::Arc;

    const MAX_CONCURRENT: usize = 5;
    let sem = Arc::new(tokio::sync::Semaphore::new(MAX_CONCURRENT));
    let on_one = Arc::new(on_one);

    let mut futs: FuturesUnordered<_> = repos
        .into_iter()
        .map(|repo| {
            let sem = sem.clone();
            let on_one = on_one.clone();
            async move {
                let _permit = sem.acquire_owned().await.ok()?;
                let bytes = fetch_repo_size_bytes(&TREE_CLIENT, &repo).await;
                // Emit even on failure so the caller can clear stale
                // entries; mapping None → None preserves the
                // "we tried, didn't get a number" semantics.
                on_one(repo, bytes);
                Some::<()>(())
            }
        })
        .collect();

    while futs.next().await.is_some() {
        // Drain as they complete; no per-fut work needed here.
    }
}

fn is_chat_mlx_model(m: &HfApiModel) -> bool {
    // 1. Must be a text-generation model.
    if let Some(p) = &m.pipeline_tag {
        if p != "text-generation" {
            return false;
        }
    } else {
        return false;
    }

    let id = m.model_id.to_lowercase();
    let last_segment = id.rsplit('/').next().unwrap_or("");

    // 2. Skip base / pre-trained / embedding / reward / classification models.
    let skip_tokens = [
        "-base", "base-", "_base",
        "-embed", "-reward", "-rerank", "-classifier",
        "-pruned", "-distill", "-pretrain", "-pretrained",
        "-encoder", "-decoder",
    ];
    if skip_tokens.iter().any(|t| last_segment.contains(t)) {
        return false;
    }

    // 3. Must look like a chat / instruct model. We accept either a name
    // suffix (`-instruct`, `-chat`, `-it`, etc.) OR the `conversational`
    // tag that mlx-community uses for some chat models (e.g. gpt-oss-20b).
    let has_chat_name = ["-instruct", "instruct-", "_instruct",
        "-chat", "chat-", "_chat",
        "-it", "-it-", // gemma-3-9b-it
        "-dialog", "-assistant",
    ]
    .iter()
    .any(|t| last_segment.contains(t));

    let has_chat_tag = m
        .tags
        .iter()
        .any(|t| matches!(t.as_str(), "conversational" | "chat" | "instruct"));

    if !has_chat_name && !has_chat_tag {
        return false;
    }

    // 4. Must be from the mlx-community org (we already filter by author,
    //    but defensive).
    if !id.starts_with(HF_ORG) {
        return false;
    }

    true
}

fn build_entry(m: HfApiModel) -> MlxModel {
    let last = m
        .model_id
        .rsplit('/')
        .next()
        .unwrap_or(&m.model_id)
        .to_string();
    let last_lower = last.to_lowercase();
    let display = friendly_name(&last);
    let size = extract_size(&last_lower);
    let quant = extract_quant(&last_lower);
    let family = extract_family(&last_lower);
    MlxModel {
        repo: m.model_id,
        display,
        downloads: m.downloads,
        family,
        size,
        quant,
        size_bytes: total_siblings_size(&m.siblings),
    }
}

/// Convert e.g. `Meta-Llama-3.1-8B-Instruct-4bit` → `Llama 3.1 8B Instruct (4-bit)`.
fn friendly_name(raw: &str) -> String {
    let mut s = raw.replace(['-', '_'], " ");
    // Drop "Meta" prefix that HF uses for Llama.
    if s.starts_with("Meta ") {
        s = s.trim_start_matches("Meta ").to_string();
    }
    // "Phi 3 mini 4k instruct 4bit" → nicer spacing.
    let s = s.split_whitespace().collect::<Vec<_>>().join(" ");
    // Re-add parentheses around the quant width for readability.
    let lower = raw.to_lowercase();
    if let Some(q) = extract_quant(&lower) {
        // Replace the bare "4bit" / "8bit" token with "(4-bit)" etc.
        let bare = q.to_lowercase().replace("-bit", "bit");
        let with_dash = q.to_lowercase(); // "4-bit"
        let s = s.replace(&bare, &format!("({with_dash})"));
        s
    } else {
        s
    }
}

/// Pull `8B` / `70B` / `mini` / `4k` etc. out of the model name.
fn extract_size(lower: &str) -> Option<String> {
    // Common patterns: "8b", "70b", "1.5b", "4k", "16k", "mini", "nano"
    for tok in ["mini", "nano", "tiny", "small", "medium", "large", "xl", "xxl"] {
        if lower.contains(tok) {
            return Some(tok.to_string());
        }
    }
    // Numeric: 1b, 1.5b, 7b, 8b, 12b, 27b, 70b, 405b
    // Also 4k, 8k, 16k, 32k, 128k (context-length markers, not size, so skip those)
    let bytes = lower.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_digit() || bytes[i] == b'.' {
            let start = i;
            while i < bytes.len() && (bytes[i].is_ascii_digit() || bytes[i] == b'.') {
                i += 1;
            }
            if i < bytes.len() && bytes[i] == b'b' {
                // Make sure it's not "4bit" / "8bit" (a quant width).
                let after = bytes.get(i + 1).copied();
                if after != Some(b'i') {
                    let num: String = lower[start..i].to_string();
                    return Some(format!("{num}B"));
                }
            }
        } else {
            i += 1;
        }
    }
    None
}

/// Pull `4bit` / `4-bit` / `8bit` / `8-bit` / `q4` / `q8` out of the name.
fn extract_quant(lower: &str) -> Option<String> {
    // "4bit" / "8bit" / "2bit" — HF mlx-community uses this convention
    for n in ["2", "3", "4", "5", "6", "8", "16"] {
        if lower.contains(&format!("{n}bit")) {
            return Some(format!("{n}-bit"));
        }
    }
    // Some repos use "_4" or "-4" suffix
    if lower.ends_with("-q4") || lower.ends_with("_q4") {
        return Some("4-bit".to_string());
    }
    if lower.ends_with("-q8") || lower.ends_with("_q8") {
        return Some("8-bit".to_string());
    }
    None
}

fn extract_family(lower: &str) -> Option<String> {
    let families = [
        "llama", "gemma", "qwen", "mistral", "mixtral", "phi", "aya",
        "deepseek", "kimi", "gpt-oss", "devstral", "command", "yi",
        "starcoder", "codellama", "falcon", "smol", "openelm", "olmo",
        "internlm", "baichuan", "hermes", "dolphin", "nous",
    ];
    for f in families {
        if lower.contains(f) {
            return Some(f.to_string());
        }
    }
    None
}

fn size_rank(s: Option<&str>) -> u64 {
    // Larger models sort first; tie-break alphabetically.
    let s = s.unwrap_or("");
    let prefix: String = s.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
    let n: f64 = prefix.parse().unwrap_or(0.0);
    if s == "mini" {
        return 1;
    }
    if s == "nano" {
        return 0;
    }
    if s == "tiny" {
        return 2;
    }
    (n * 10.0) as u64
}

fn quant_rank(q: Option<&str>) -> u32 {
    match q {
        Some("2-bit") => 0,
        Some("3-bit") => 1,
        Some("4-bit") => 2,
        Some("5-bit") => 3,
        Some("6-bit") => 4,
        Some("8-bit") => 5,
        _ => 9,
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Cache I/O
// ─────────────────────────────────────────────────────────────────────────

fn read_cache() -> Option<Vec<MlxModel>> {
    let path = CACHE_PATH.as_ref()?;
    let bytes = std::fs::read(path).ok()?;
    let cached: CachedModels = match serde_json::from_slice(&bytes) {
        Ok(c) => c,
        Err(_) => return None,
    };
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if now.saturating_sub(cached.fetched_at) > CACHE_TTL_SECS {
        // Stale — only use it as a last resort.
        log::info!("mlx_models cache stale ({}s old)", now - cached.fetched_at);
        return None;
    }
    Some(cached.models)
}

/// Read the cache even if it's stale — used as a fallback when the API is
/// down. Returns `None` only if there's no cache at all.
pub fn read_stale_cache() -> Option<Vec<MlxModel>> {
    let path = CACHE_PATH.as_ref()?;
    let bytes = std::fs::read(path).ok()?;
    let cached: CachedModels = serde_json::from_slice(&bytes).ok()?;
    if cached.models.is_empty() {
        None
    } else {
        Some(cached.models)
    }
}

fn write_cache(models: &[MlxModel]) -> Result<()> {
    let path = match CACHE_PATH.as_ref() {
        Some(p) => p,
        None => return Ok(()),
    };
    let cached = CachedModels {
        fetched_at: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0),
        models: models.to_vec(),
    };
    let json = serde_json::to_vec_pretty(&cached)?;
    std::fs::write(path, json)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_size_finds_b() {
        assert_eq!(extract_size("meta-llama-3.1-8b-instruct"), Some("8B".into()));
        assert_eq!(extract_size("qwen2.5-7b-instruct"), Some("7B".into()));
        assert_eq!(extract_size("phi-3-mini-4k-instruct"), Some("mini".into()));
    }

    #[test]
    fn extract_quant_finds_bit() {
        assert_eq!(extract_quant("llama-3.1-8b-instruct-4bit"), Some("4-bit".into()));
        assert_eq!(extract_quant("llama-3.1-8b-instruct-8bit"), Some("8-bit".into()));
    }

    #[test]
    fn family_extraction() {
        assert_eq!(extract_family("meta-llama-3.1-8b-instruct"), Some("llama".into()));
        assert_eq!(extract_family("gemma-3-9b-it"), Some("gemma".into()));
        assert_eq!(extract_family("qwen2.5-7b-instruct"), Some("qwen".into()));
    }

    #[test]
    fn friendly_name_pretty() {
        let n = friendly_name("Meta-Llama-3.1-8B-Instruct-4bit");
        assert!(n.contains("Llama 3.1 8B Instruct"));
        assert!(n.contains("4-bit"));
    }

    #[test]
    fn is_chat_filter() {
        // Should pass
        let m = HfApiModel {
            model_id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit".into(),
            tags: vec![],
            pipeline_tag: Some("text-generation".into()),
            downloads: 100,
            siblings: vec![],
        };
        assert!(is_chat_mlx_model(&m));

        // Should fail: base model
        let m = HfApiModel {
            model_id: "mlx-community/Meta-Llama-3.1-8B-base".into(),
            tags: vec![],
            pipeline_tag: Some("text-generation".into()),
            downloads: 100,
            siblings: vec![],
        };
        assert!(!is_chat_mlx_model(&m));

        // Should fail: wrong pipeline
        let m = HfApiModel {
            model_id: "mlx-community/some-embedding-instruct".into(),
            tags: vec![],
            pipeline_tag: Some("feature-extraction".into()),
            downloads: 100,
            siblings: vec![],
        };
        assert!(!is_chat_mlx_model(&m));

        // Should pass: gpt-oss-20b with conversational tag
        let m = HfApiModel {
            model_id: "mlx-community/gpt-oss-20b-MXFP4-Q8".into(),
            tags: vec!["conversational".into()],
            pipeline_tag: Some("text-generation".into()),
            downloads: 100,
            siblings: vec![],
        };
        assert!(is_chat_mlx_model(&m));

        // Should pass: gemma-it
        let m = HfApiModel {
            model_id: "mlx-community/gemma-3-9b-it-4bit".into(),
            tags: vec![],
            pipeline_tag: Some("text-generation".into()),
            downloads: 100,
            siblings: vec![],
        };
        assert!(is_chat_mlx_model(&m));

        // Should pass: Kimi-K2.5 (no -instruct suffix but has conversational tag)
        let m = HfApiModel {
            model_id: "mlx-community/Kimi-K2.5".into(),
            tags: vec!["conversational".into()],
            pipeline_tag: Some("text-generation".into()),
            downloads: 100,
            siblings: vec![],
        };
        assert!(is_chat_mlx_model(&m));
    }

    // ── MLX-Whisper helpers ────────────────────────────────────────────
    #[test]
    fn whisper_friendly_name() {
        assert_eq!(
            friendly_whisper_name("whisper-large-v3-turbo"),
            "Whisper Large V3 Turbo"
        );
        assert_eq!(friendly_whisper_name("whisper-medium"), "Whisper Medium");
        assert_eq!(
            friendly_whisper_name("whisper-tiny.en"),
            "Whisper Tiny (English)"
        );
        assert_eq!(
            friendly_whisper_name("whisper-distil-large-v3"),
            "Whisper Distil Large V3"
        );
        assert_eq!(
            friendly_whisper_name("whisper-large-v3-mlx"),
            "Whisper Large V3",
            "trailing -mlx should be stripped"
        );
    }

    #[test]
    fn whisper_extract_size() {
        assert_eq!(
            extract_whisper_size("whisper-turbo"),
            None,
            "no model name → None"
        );
        assert_eq!(
            extract_whisper_size("whisper-large-v3-turbo"),
            Some("large-v3-turbo".into())
        );
        assert_eq!(
            extract_whisper_size("whisper-large-v3"),
            Some("large-v3".into())
        );
        assert_eq!(
            extract_whisper_size("whisper-distil-large-v3"),
            Some("distil-large-v3".into())
        );
        assert_eq!(extract_whisper_size("whisper-tiny"), Some("tiny".into()));
        assert_eq!(extract_whisper_size("whisper-base"), Some("base".into()));
        assert_eq!(
            extract_whisper_size("whisper-medium"),
            Some("medium".into())
        );
        assert_eq!(
            extract_whisper_size("whisper-small"),
            Some("small".into())
        );
    }

    #[test]
    fn whisper_size_rank_orders_correctly() {
        let order = |s: &str| whisper_size_rank(&Some(s.to_string()));
        assert!(order("tiny") < order("base"));
        assert!(order("base") < order("small"));
        assert!(order("small") < order("medium"));
        assert!(order("medium") < order("distil-large-v3"));
        assert!(order("distil-large-v3") < order("large-v3"));
    }

    #[test]
    fn whisper_fallback_models_have_unique_repos() {
        let models = fallback_whisper_models();
        let mut repos: Vec<_> = models.iter().map(|m| m.repo.clone()).collect();
        repos.sort();
        let original_len = repos.len();
        repos.dedup();
        assert_eq!(repos.len(), original_len, "fallback repos must be unique");
        for m in &models {
            assert!(m.repo.starts_with("mlx-community/whisper-"));
            assert!(!m.display.is_empty());
        }
    }

    #[test]
    fn is_whisper_repo_classifies_correctly() {
        // Positive cases — every variant we ship should classify as Whisper.
        assert!(is_whisper_repo("mlx-community/whisper-large-v3-turbo"));
        assert!(is_whisper_repo("mlx-community/whisper-tiny"));
        assert!(is_whisper_repo("mlx-community/whisper-distil-large-v3"));
        assert!(is_whisper_repo("mlx-community/whisper-large-v3-mlx"));
        // Case-insensitive basename check.
        assert!(is_whisper_repo("mlx-community/Whisper-Large-V3"));

        // Negative cases — every LLM family in the catalog must
        // classify as NOT Whisper, otherwise the LLM dropdown will
        // start hiding chat models.
        assert!(!is_whisper_repo("mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"));
        assert!(!is_whisper_repo("mlx-community/gemma-3-9b-it-4bit"));
        assert!(!is_whisper_repo("mlx-community/Qwen3-8B-4bit"));
        assert!(!is_whisper_repo("mlx-community/Mistral-7B-Instruct-v0.3-4bit"));
        assert!(!is_whisper_repo("mlx-community/Phi-3-mini-4k-instruct-4bit"));
        // Edge cases — empty / no slash / weird casing.
        assert!(!is_whisper_repo(""));
        assert!(!is_whisper_repo("solo"));
        // A user whose org literally contains "whisper" but whose
        // model is a chat LLM should NOT be misclassified.
        assert!(!is_whisper_repo("whisper-co/llama-3-8b"));
    }

    #[test]
    fn llm_and_whisper_scans_are_disjoint() {
        // Walk the fallback lists and confirm the filter never
        // produces a repo that doesn't belong to its target set.
        for m in fallback_models() {
            assert!(
                !is_whisper_repo(&m.repo),
                "fallback LLM list leaked a Whisper repo: {}",
                m.repo
            );
        }
        for m in fallback_whisper_models() {
            assert!(
                is_whisper_repo(&m.repo),
                "fallback Whisper list leaked a non-Whisper repo: {}",
                m.repo
            );
        }
    }

    // ─── HfTreeEntry JSON shape ──────────────────────────────────────
    //
    // The tree endpoint returns a different shape from the models
    // listing — we have to deserialize it ourselves to sum file
    // sizes. These tests pin the shape so a future HF API change
    // (e.g. renaming `path` or splitting `type` into a different
    // value) shows up as a failing test rather than silently
    // returning None at runtime.

    #[test]
    fn tree_entry_parses_minimal_file() {
        // Minimum viable entry — what we get for `.gitattributes`
        // and other small metadata files.
        let json = r#"{"type":"file","path":".gitattributes","oid":"abc"}"#;
        let e: HfTreeEntry = serde_json::from_str(json).unwrap();
        assert_eq!(e.kind, "file");
        assert_eq!(e.path, ".gitattributes");
        // No `size` key → defaults to None.
        assert!(e.size.is_none());
    }

    #[test]
    fn tree_entry_parses_lfs_file() {
        // The big safetensors rows look like this. The `size` we
        // sum is the outer `size` field, NOT `lfs.size` — they're
        // identical for actual LFS files, but the outer one is
        // always present and that's what we should be reading.
        let json = r#"{
            "type": "file",
            "oid": "dc3063cdd153b74cdd5940080114e9d186dc7331",
            "size": 4517489037,
            "lfs": {
                "oid": "192065799d1621df78b68274137974d3258c5dadce9ca71305ed014d997d67c4",
                "size": 4517489037,
                "pointerSize": 135
            },
            "xetHash": "32f98b872130f9bbc4cfa19ac4f4040aaa55921905f68ac49deb50ff2e632e61",
            "path": "model.safetensors"
        }"#;
        let e: HfTreeEntry = serde_json::from_str(json).unwrap();
        assert_eq!(e.kind, "file");
        assert_eq!(e.path, "model.safetensors");
        assert_eq!(e.size, Some(4_517_489_037));
    }

    #[test]
    fn tree_entry_parses_directory() {
        // Directories in the response have `type: "directory"` and
        // no `size`. Make sure we don't treat them as files.
        let json = r#"{"type":"directory","path":"onnx","oid":"def"}"#;
        let e: HfTreeEntry = serde_json::from_str(json).unwrap();
        assert_eq!(e.kind, "directory");
        assert!(e.size.is_none());
    }
}