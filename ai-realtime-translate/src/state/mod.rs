//! Shared application state — atomic state, async event channel, derived snapshots.
//!
//! In the Python version this was a `dict` plus a `deque` + lock. Here we use
//! `parking_lot::Mutex` for synchronous fields + `tokio::sync::broadcast` for
//! events, which the Dioxus UI subscribes to via a `use_signal` + spawn task.

use crate::config::*;
use crate::system::DeviceSpecs;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::{broadcast, Mutex as AsyncMutex};

/// Event broadcast to the UI from the audio/STT/LLM pipeline.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", content = "data")]
pub enum AppEvent {
    /// Full state snapshot (also used on SSE initial connect). Boxed to
    /// keep the enum a uniform, small size — `PublicState` is ~800 bytes
    /// because of the catalog history; without the Box every variant
    /// pays that cost on the wire and in the broadcast channel.
    State(Box<PublicState>),
    /// Level meter tick (0..=1).
    Level { v: f32 },
    /// A new transcript + translation pair.
    Transcript(TranscriptEntry),
    /// Informational toast.
    Info { msg: String },
    /// Successful operation toast.
    Ok { msg: String },
    /// Error toast (also shown as red banner).
    Error { msg: String },
    /// Error toast with a clickable action button (e.g. "Open System
    /// Settings" for TCC denials). The toast UI renders `msg` alongside
    /// an inline button labelled `action_label`; clicking it opens
    /// `action_url` via the OS shell (e.g. an `x-apple.systempreferences:`
    /// URL on macOS).
    ErrorWithAction {
        msg: String,
        action_label: String,
        action_url: String,
    },
    /// The downloaded-models list has changed (after a download or delete).
    /// Frontend should re-render the Models modal accordingly.
    DownloadedModelsChanged,
}

/// One segment in the dual-pane feed.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TranscriptEntry {
    pub ts: f64,
    pub src: String,
    pub tgt: String,
    pub src_lang: String,
    pub tgt_lang: String,
    pub latency: EntryLatency,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct EntryLatency {
    pub stt: f32,
    pub llm: f32,
}

/// Snapshot of the public state — sent to the UI on every change.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PublicState {
    pub listening: bool,
    pub device: String,
    pub devices: Vec<DeviceInfo>,
    /// Name of the audio output device Foundry should route all system
    /// audio through while capturing. When non-empty AND different
    /// from the current macOS default output, the pipeline will
    /// programmatically switch the system default to this device
    /// before opening the SCK capture, then restore on Stop.
    /// Empty string = leave system output alone.
    #[serde(default)]
    pub output_device: String,
    /// All output devices the OS reports. Populated once on boot
    /// (plus a "(leave system default)" pseudo-entry the UI prepends).
    #[serde(default)]
    pub output_devices: Vec<DeviceInfo>,
    pub src_lang: String,
    pub tgt_lang: String,
    /// Full HuggingFace repo id of the active translation model
    /// (e.g. `mlx-community/Meta-Llama-3.1-8B-Instruct-4bit`). Empty when
    /// no model is selected.
    pub model: String,
    /// Friendly display name of the active model (e.g. `Llama 3.1 8B Instruct (4-bit)`).
    #[serde(default)]
    pub model_display: String,
    /// Available MLX models for the dropdown. Each entry has `repo` (HF id)
    /// and `display` (friendly name).
    pub models: Vec<MlxModelEntry>,
    /// True after we've finished the initial HuggingFace fetch. Until then
    /// the dropdown shows the hardcoded fallback list.
    #[serde(default)]
    pub models_loaded: bool,
    /// HF repo ids that are already downloaded to the local HF cache
    /// (`~/.cache/huggingface/hub/`). The toolbar dropdown only shows
    /// these — the full catalog lives in the Models modal.
    #[serde(default)]
    pub downloaded_models: Vec<String>,
    /// HF repo id currently being downloaded (None when idle). The Models
    /// modal renders a progress bar for this row.
    #[serde(default)]
    pub downloading: Option<String>,
    /// Download progress 0.0..=1.0 for the row in `downloading`.
    #[serde(default)]
    pub download_progress: f32,

    // ─── STT (MLX-Whisper only — whisper.cpp backend removed) ──────
    /// Full HF repo id of the active STT model
    /// (e.g. `mlx-community/whisper-large-v3-turbo`).
    pub wmodel: String,
    /// Friendly display name of the active STT model
    /// (e.g. `Whisper Large V3 Turbo`).
    #[serde(default)]
    pub wmodel_display: String,
    /// Catalog of MLX-Whisper models pulled from HuggingFace.
    pub wmodels: Vec<MlxModelEntry>,
    /// True after the initial HF fetch for STT models completes.
    #[serde(default)]
    pub wmodels_loaded: bool,
    /// Downloaded STT repos (same naming convention as `downloaded_models`).
    #[serde(default)]
    pub downloaded_wmodels: Vec<String>,
    /// STT model currently downloading (separate from LLM download slot
    /// so progress UIs don't share state).
    #[serde(default)]
    pub downloading_wmodel: Option<String>,
    /// STT download progress 0.0..=1.0.
    #[serde(default)]
    pub wmodel_download_progress: f32,

    pub use_mlx_lm: bool,
    pub concise_translation: bool,
    pub vad_silence_threshold: f32,
    pub vad_max_speech_duration: f32,
    pub glossary: String,
    pub custom_prompt: String,
    pub history: Vec<TranscriptEntry>,
    pub stt_busy: bool,
    pub llm_busy: bool,
    pub backends: BackendInfo,
    /// Monotonic counter the UI bumps to ask the audio pipeline to
    /// retry opening the capture (typically after the user clicks
    /// "Open System Settings" on a permission-denied toast). The
    /// pipeline compares this against the value it saw on the previous
    /// loop iteration and resets its TCC-denial latch when it changes —
    /// no need for the user to toggle Listen off and back on.
    #[serde(default)]
    pub audio_retry_signal: u64,

    // ─── Host + model metadata (set on boot, refreshed on demand) ───
    /// Hardware specs of the machine running Foundry. Populated once at
    /// startup; the modal renders a small "Device" card with these.
    /// (Named `host` to avoid collision with the audio-input `device`
    /// string above.)
    #[serde(default)]
    pub host: Option<DeviceSpecs>,
    /// HF repo id → catalog-reported total bytes (sum of
    /// `siblings[].size` from the HF API). Populated when the catalog
    /// fetch completes. Empty for custom repos that aren't in any
    /// catalog.
    #[serde(default)]
    pub catalog_sizes: HashMap<String, u64>,
    /// HF repo id → actual disk size of the local HF cache blobs.
    /// Repopulated on every `scan_downloaded()` call so it reflects
    /// deletions / partial downloads.
    #[serde(default)]
    pub downloaded_sizes: HashMap<String, u64>,
    /// HF repo id → formatted speed string, e.g. `"32 tok/s"` for
    /// chat, `"4.8× realtime"` for whisper. Populated by the
    /// `BenchmarkModel` / `BenchmarkWhisperModel` UI commands.
    #[serde(default)]
    pub model_speeds: HashMap<String, String>,
    #[serde(default)]
    pub wmodel_speeds: HashMap<String, String>,
    /// Repo id of a chat model whose speed benchmark is currently
    /// running (background task). When `Some(repo)` the Models modal
    /// shows a "Testing…" spinner in that row instead of a Test
    /// button.
    #[serde(default)]
    pub benchmarking: Option<String>,
    /// Same as `benchmarking` but for Whisper models.
    #[serde(default)]
    pub wmodel_benchmarking: Option<String>,
}

/// UI-side mirror of `crate::llm::mlx_models::MlxModel`. Kept separate so
/// `state` doesn't have to depend on the llm module graph.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MlxModelEntry {
    pub repo: String,
    pub display: String,
    /// Quantization hint extracted from the repo id (e.g. `"4-bit"`,
    /// `"8-bit"`). `None` when it can't be determined — the model
    /// might be a custom repo, a non-quantized base model, or an
    /// older fetch that didn't carry the field. The Models modal
    /// uses it to refine the VRAM estimate.
    #[serde(default)]
    pub quant: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct BackendInfo {
    pub mlx_whisper_available: bool,
    pub mlx_lm_available: bool,
    pub system_audio_available: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DeviceInfo {
    pub index: i32,
    pub name: String,
    pub channels: u32,
    pub sample_rate: f32,
}

impl PublicState {
    pub fn default_for(backends: BackendInfo) -> Self {
        Self {
            listening: false,
            device: String::new(),
            devices: vec![],
            output_device: String::new(),
            output_devices: vec![],
            src_lang: "auto".into(),
            tgt_lang: "th".into(),
            model: String::new(),
            model_display: String::new(),
            models: vec![],
            models_loaded: false,
            downloaded_models: Vec::new(),
            downloading: None,
            download_progress: 0.0,
            wmodel: String::new(),
            wmodel_display: String::new(),
            wmodels: vec![],
            wmodels_loaded: false,
            downloaded_wmodels: Vec::new(),
            downloading_wmodel: None,
            wmodel_download_progress: 0.0,
            use_mlx_lm: true,
            concise_translation: false,
            vad_silence_threshold: 0.8,
            vad_max_speech_duration: 5.0,
            glossary: String::new(),
            custom_prompt: String::new(),
            history: vec![],
            stt_busy: false,
            llm_busy: false,
            backends,
            audio_retry_signal: 0,
            host: None,
            catalog_sizes: HashMap::new(),
            downloaded_sizes: HashMap::new(),
            model_speeds: HashMap::new(),
            wmodel_speeds: HashMap::new(),
            benchmarking: None,
            wmodel_benchmarking: None,
        }
    }
}

/// Inner state guarded by a sync mutex (for cheap reads from control thread).
pub struct InnerState {
    pub pub_state: PublicState,
    pub history: VecDeque<TranscriptEntry>,
}

impl InnerState {
    pub fn new(backends: BackendInfo) -> Self {
        Self {
            pub_state: PublicState::default_for(backends),
            history: VecDeque::with_capacity(UI_HISTORY_LIMIT + 16),
        }
    }
}

/// Top-level handle that every subsystem owns a clone of.
#[derive(Clone)]
pub struct AppState {
    pub inner: Arc<parking_lot::Mutex<InnerState>>,
    pub events: broadcast::Sender<AppEvent>,
    /// Inbound command channel — UI components send `UiCommand`s here
    /// to request downloads, deletes, or model selection changes that
    /// need async work or background tasks.
    pub commands: tokio::sync::mpsc::UnboundedSender<UiCommand>,
    /// Async mutex around any long-lived mutable resource that doesn't fit
    /// in `InnerState` (e.g. the audio stream guard). Reserved for future
    /// use; the pipeline currently uses the watch channel on the handle
    /// for its own serialization.
    #[allow(dead_code)]
    pub audio_lock: Arc<AsyncMutex<()>>,
}

/// Async commands the UI can send to the app.
#[derive(Debug, Clone)]
pub enum UiCommand {
    /// Download an MLX chat model repo from HuggingFace.
    DownloadModel { repo: String },
    /// Abort an in-flight chat model download (kills the python
    /// subprocess and emits a "Cancelled" toast).
    CancelDownload { repo: String },
    /// Delete a downloaded chat model from the local HF cache.
    DeleteModel { repo: String },
    /// Switch the active chat model.
    UseModel { repo: String },
    /// Run a speed benchmark on a downloaded chat model (loads it
    /// in a background python subprocess, times ~50 generated tokens,
    /// caches the result in `model_speeds`).
    BenchmarkModel { repo: String },
    /// Download an MLX-Whisper (STT) model repo from HuggingFace.
    DownloadWhisperModel { repo: String },
    /// Abort an in-flight Whisper model download.
    CancelWhisperDownload { repo: String },
    /// Delete a downloaded Whisper model from the local HF cache.
    DeleteWhisperModel { repo: String },
    /// Switch the active STT model.
    UseWhisperModel { repo: String },
    /// Run a speed benchmark on a downloaded Whisper model
    /// (transcribes 1s of silence, caches the realtime factor).
    BenchmarkWhisperModel { repo: String },
}

impl AppState {
    /// Construct the AppState. The UiCommand driver task is spawned
    /// here on the current tokio runtime (Dioxus desktop uses tokio by
    /// default), so callers don't need to manage the receiver.
    pub fn new(backends: BackendInfo) -> Self {
        let (tx, _rx) = broadcast::channel(1024);
        let (cmd_tx, cmd_rx) = tokio::sync::mpsc::unbounded_channel::<UiCommand>();
        let state = Self {
            inner: Arc::new(parking_lot::Mutex::new(InnerState::new(backends))),
            events: tx,
            commands: cmd_tx,
            audio_lock: Arc::new(AsyncMutex::new(())),
        };
        let driver_state = state.clone();
        tokio::spawn(async move {
            crate::app::run_command_driver(driver_state, cmd_rx).await;
        });
        state
    }

    /// Emit an event; never blocks, drops if no subscribers.
    pub fn emit(&self, ev: AppEvent) {
        let _ = self.events.send(ev);
    }

    /// Send a UI command (download / delete / use). Drops silently if
    /// the receiver has been closed.
    pub fn send_cmd(&self, cmd: UiCommand) {
        let _ = self.commands.send(cmd);
    }

    /// Snapshot the current public state.
    pub fn snapshot(&self) -> PublicState {
        let g = self.inner.lock();
        let mut s = g.pub_state.clone();
        s.history = g.history.iter().cloned().collect();
        s
    }

    /// Apply a control update (mirrors `Handler._apply_control` in Python).
    pub fn apply_control(&self, patch: serde_json::Value) {
        let mut g = self.inner.lock();
        let s = &mut g.pub_state;
        if let Some(v) = patch.get("listening").and_then(|x| x.as_bool()) {
            s.listening = v;
        }
        if let Some(v) = patch.get("device").and_then(|x| x.as_str()) {
            s.device = v.to_string();
        }
        if let Some(v) = patch.get("output_device").and_then(|x| x.as_str()) {
            s.output_device = v.to_string();
        }
        if let Some(v) = patch.get("src_lang").and_then(|x| x.as_str()) {
            s.src_lang = v.to_string();
        }
        if let Some(v) = patch.get("tgt_lang").and_then(|x| x.as_str()) {
            s.tgt_lang = v.to_string();
        }
        if let Some(v) = patch.get("model").and_then(|x| x.as_str()) {
            s.model = v.to_string();
            // Auto-resolve display name from the model list so the UI
            // doesn't have to look it up itself.
            if let Some(entry) = s.models.iter().find(|m| m.repo == v) {
                s.model_display = entry.display.clone();
            } else {
                // Custom repo (user typed one) — derive a display name from
                // the last path segment.
                s.model_display = v
                    .rsplit('/')
                    .next()
                    .unwrap_or(v)
                    .replace('-', " ")
                    .to_string();
            }
        }
        if let Some(v) = patch.get("model_display").and_then(|x| x.as_str()) {
            s.model_display = v.to_string();
        }
        if let Some(v) = patch.get("models_loaded").and_then(|x| x.as_bool()) {
            s.models_loaded = v;
        }
        if let Some(v) = patch.get("downloaded_models").and_then(|x| x.as_array()) {
            s.downloaded_models = v
                .iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect();
        }
        if let Some(v) = patch.get("downloading").and_then(|x| x.as_str()) {
            s.downloading = Some(v.to_string());
        }
        if patch.get("downloading").map(|x| x.is_null()).unwrap_or(false) {
            s.downloading = None;
            s.download_progress = 0.0;
        }
        if let Some(v) = patch.get("download_progress").and_then(|x| x.as_f64()) {
            s.download_progress = v as f32;
        }
        if let Some(v) = patch.get("wmodel").and_then(|x| x.as_str()) {
            s.wmodel = v.to_string();
            // Auto-resolve display name from catalog (falls back to
            // last path segment for custom repos).
            s.wmodel_display = s
                .wmodels
                .iter()
                .find(|m| m.repo == s.wmodel)
                .map(|m| m.display.clone())
                .unwrap_or_else(|| {
                    s.wmodel
                        .rsplit('/')
                        .next()
                        .unwrap_or(&s.wmodel)
                        .to_string()
                });
        }
        if let Some(v) = patch.get("downloaded_wmodels").and_then(|x| x.as_array()) {
            s.downloaded_wmodels = v
                .iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect();
        }
        if let Some(v) = patch.get("downloading_wmodel").and_then(|x| x.as_str()) {
            s.downloading_wmodel = Some(v.to_string());
        }
        if patch
            .get("downloading_wmodel")
            .map(|x| x.is_null())
            .unwrap_or(false)
        {
            s.downloading_wmodel = None;
            s.wmodel_download_progress = 0.0;
        }
        if let Some(v) = patch.get("wmodel_download_progress").and_then(|x| x.as_f64()) {
            s.wmodel_download_progress = v as f32;
        }
        if let Some(v) = patch.get("wmodels_loaded").and_then(|x| x.as_bool()) {
            s.wmodels_loaded = v;
        }
        if let Some(v) = patch.get("use_mlx_lm").and_then(|x| x.as_bool()) {
            s.use_mlx_lm = v;
        }
        if let Some(v) = patch.get("concise_translation").and_then(|x| x.as_bool()) {
            s.concise_translation = v;
        }
        if let Some(v) = patch.get("vad_silence_threshold").and_then(|x| x.as_f64()) {
            s.vad_silence_threshold = v as f32;
        }
        if let Some(v) = patch.get("vad_max_speech_duration").and_then(|x| x.as_f64()) {
            s.vad_max_speech_duration = v as f32;
        }
        if let Some(v) = patch.get("audio_retry_signal").and_then(|x| x.as_u64()) {
            // Only advance — never go backwards. A stale State event
            // replayed into apply_control shouldn't accidentally
            // cancel a retry the user already requested.
            if v > s.audio_retry_signal {
                s.audio_retry_signal = v;
            }
        }
        if let Some(v) = patch.get("glossary").and_then(|x| x.as_str()) {
            s.glossary = v.chars().take(2000).collect();
        }
        if let Some(v) = patch.get("custom_prompt").and_then(|x| x.as_str()) {
            s.custom_prompt = v.chars().take(4000).collect();
        }
        if patch.get("clear").and_then(|x| x.as_bool()).unwrap_or(false) {
            g.history.clear();
        }
        drop(g);
        self.emit(AppEvent::State(Box::new(self.snapshot())));
    }

    /// Append a transcript entry to the history and emit.
    pub fn push_entry(&self, entry: TranscriptEntry) {
        let mut g = self.inner.lock();
        g.history.push_back(entry.clone());
        while g.history.len() > UI_HISTORY_LIMIT {
            g.history.pop_front();
        }
        g.pub_state.history = g.history.iter().cloned().collect();
        drop(g);
        self.emit(AppEvent::Transcript(entry));
    }
}

/// Detect available backends at startup. The Python version auto-detects MLX;
/// in Rust we shell out to `python3 -c 'import mlx_whisper'` for the bridge.
pub fn detect_backends() -> BackendInfo {
    let (mlx_whisper, mlx_lm) = crate::stt::mlx_bridge::probe();
    BackendInfo {
        mlx_whisper_available: mlx_whisper,
        mlx_lm_available: mlx_lm,
        system_audio_available: cfg!(target_os = "macos"),
    }
}