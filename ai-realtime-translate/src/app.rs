//! Top-level Dioxus app — wires up the audio + STT + LLM pipelines and hosts
//! the UI tree.

use crate::audio::capture::list_input_devices;
use crate::audio::pipeline;
use crate::components::drawer::Drawer;
use crate::components::feed::Feed;
use crate::components::footer::Footer;
use crate::components::models_modal::ModelsModal;
use crate::components::status_pill::StatusPill;
use crate::components::toolbar::Toolbar;
use crate::components::waveform::Waveform;
use crate::llm::benchmark;
use crate::llm::mlx_models::{self, MlxModel};
use crate::state::{detect_backends, AppEvent, AppState, MlxModelEntry, PublicState, UiCommand};
use dioxus::desktop::{Config, LogicalSize, WindowBuilder};
use dioxus::prelude::*;
use std::time::Duration;

/// Consume `UiCommand`s from the UI (downloads, deletes, model swaps).
/// Spawned once at app startup with the receiver returned by
/// `AppState::new`. Drives long-running background work and keeps
/// `PublicState::downloaded_models` / `downloading` in sync.
pub async fn run_command_driver(
    st: AppState,
    mut rx: tokio::sync::mpsc::UnboundedReceiver<UiCommand>,
) {
    use crate::llm::mlx_models::DownloadOutcome;
    use std::collections::HashMap;
    use std::sync::Arc;

    // Per-repo bookkeeping. `active` is what we use to dedupe (no two
    // simultaneous downloads of the same repo); `cancel_handles` lets us
    // fire a cancel signal at a specific in-flight download.
    //
    // Both maps are wrapped in Arc<Mutex<>> so the spawned download
    // tasks can clean themselves up on completion — without that, a
    // finished download would leave a stale entry in `active` and the
    // user could never re-download the same repo on a retry.
    let active: Arc<parking_lot::Mutex<HashMap<String, tokio::task::JoinHandle<()>>>> =
        Arc::new(parking_lot::Mutex::new(HashMap::new()));
    let cancel_handles: Arc<
        parking_lot::Mutex<HashMap<String, tokio::sync::oneshot::Sender<()>>>,
    > = Arc::new(parking_lot::Mutex::new(HashMap::new()));

    while let Some(cmd) = rx.recv().await {
        match cmd {
            UiCommand::DownloadModel { repo } => {
                {
                    let g = active.lock();
                    if g.contains_key(&repo) {
                        continue;
                    }
                }
                let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel::<()>();
                cancel_handles.lock().insert(repo.clone(), cancel_tx);

                let st_inner = st.clone();
                let repo_clone = repo.clone();
                let active_inner = Arc::clone(&active);
                let cancel_inner = Arc::clone(&cancel_handles);
                let handle = tokio::spawn(async move {
                    // Mark as downloading.
                    {
                        let mut g = st_inner.inner.lock();
                        g.pub_state.downloading = Some(repo_clone.clone());
                        g.pub_state.download_progress = 0.0;
                        drop(g);
                        st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                    }

                    let res = mlx_models::download_model(&repo_clone, cancel_rx).await;
                    let outcome: DownloadOutcome = match res {
                        Ok((mut progress_rx, done_rx)) => {
                            // `done_rx` is !Unpin — pin it once so we
                            // can poll it across iterations of the
                            // select! loop without moving it.
                            let mut done_rx = std::pin::pin!(done_rx);
                            loop {
                                tokio::select! {
                                    biased;
                                    pct = progress_rx.recv() => {
                                        if let Some(p) = pct {
                                            let mut g = st_inner.inner.lock();
                                            if g.pub_state.downloading.as_deref() == Some(&repo_clone) {
                                                g.pub_state.download_progress = p;
                                                drop(g);
                                                st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                                            }
                                        } else {
                                            // Progress channel closed
                                            // without done_rx firing —
                                            // odd, but fall through to
                                            // the done receiver to learn
                                            // the terminal outcome.
                                            break loop_finish(&mut done_rx).await;
                                        }
                                    }
                                    result = &mut done_rx => {
                                        break match result {
                                            Ok(o) => o,
                                            Err(_) => DownloadOutcome::Failed(anyhow::anyhow!(
                                                "download task ended without reporting outcome"
                                            )),
                                        };
                                    }
                                }
                            }
                        }
                        Err(e) => DownloadOutcome::Failed(e),
                    };

                    // Apply terminal outcome to state + emit toasts.
                    match outcome {
                        DownloadOutcome::Completed => {
                            log::info!("download complete: {repo_clone}");
                            // Filter to LLM-only — the HF cache also
                            // holds any Whisper STT models the user
                            // has downloaded, and we must not let
                            // those leak into the LLM dropdown.
                            let scanned = mlx_models::scan_downloaded_llms();
                            let mut downloaded: Vec<String> =
                                scanned.iter().map(|(r, _)| r.clone()).collect();
                            downloaded.sort();
                            let mut g = st_inner.inner.lock();
                            g.pub_state.downloaded_models = downloaded;
                            g.pub_state.downloaded_sizes.clear();
                            for (repo, bytes) in scanned {
                                g.pub_state.downloaded_sizes.insert(repo, bytes);
                            }
                            g.pub_state.downloading = None;
                            g.pub_state.download_progress = 0.0;
                            drop(g);
                            st_inner.emit(AppEvent::Ok {
                                msg: format!("✓ Downloaded {}", repo_clone),
                            });
                            st_inner.emit(AppEvent::DownloadedModelsChanged);
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                        DownloadOutcome::Cancelled => {
                            log::info!("download cancelled: {repo_clone}");
                            let mut g = st_inner.inner.lock();
                            g.pub_state.downloading = None;
                            g.pub_state.download_progress = 0.0;
                            drop(g);
                            st_inner.emit(AppEvent::Info {
                                msg: format!("Cancelled download of {}", repo_clone),
                            });
                            st_inner.emit(AppEvent::DownloadedModelsChanged);
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                        DownloadOutcome::Failed(e) => {
                            log::warn!("download failed: {e}");
                            let mut g = st_inner.inner.lock();
                            g.pub_state.downloading = None;
                            g.pub_state.download_progress = 0.0;
                            drop(g);
                            st_inner.emit(AppEvent::Error {
                                msg: format!("Download failed: {e}"),
                            });
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                    }

                    // Cleanup: release the dedup slot and the cancel
                    // sender so a retry (or a different model) can run.
                    active_inner.lock().remove(&repo_clone);
                    cancel_inner.lock().remove(&repo_clone);
                });
                active.lock().insert(repo, handle);
            }
            UiCommand::CancelDownload { repo } => {
                if let Some(tx) = cancel_handles.lock().remove(&repo) {
                    let _ = tx.send(());
                    // The spawned task will observe cancel, kill the
                    // child, and clean up `active` + `cancel_handles`
                    // itself. Nothing more to do here.
                }
            }
            UiCommand::DeleteModel { repo } => match mlx_models::delete_model(&repo) {
                Ok(true) => {
                    // LLM-only scan so a deleted LLM doesn't bring
                    // Whisper repos back into `downloaded_models`.
                    let scanned = mlx_models::scan_downloaded_llms();
                    let mut downloaded: Vec<String> =
                        scanned.iter().map(|(r, _)| r.clone()).collect();
                    downloaded.sort();
                    let mut g = st.inner.lock();
                    g.pub_state.downloaded_models = downloaded;
                    g.pub_state.downloaded_sizes.remove(&repo);
                    if g.pub_state.model == repo {
                        g.pub_state.model = String::new();
                        g.pub_state.model_display = String::new();
                    }
                    drop(g);
                    st.emit(AppEvent::Ok {
                        msg: format!("Deleted {}", repo),
                    });
                    st.emit(AppEvent::DownloadedModelsChanged);
                    st.emit(AppEvent::State(Box::new(st.snapshot())));
                }
                Ok(false) => {
                    st.emit(AppEvent::Info {
                        msg: format!("{} was not in cache", repo),
                    });
                }
                Err(e) => {
                    st.emit(AppEvent::Error {
                        msg: format!("Delete failed: {e}"),
                    });
                }
            },
            UiCommand::UseModel { repo } => {
                let mut g = st.inner.lock();
                g.pub_state.model = repo.clone();
                if let Some(entry) = g.pub_state.models.iter().find(|m| m.repo == repo) {
                    g.pub_state.model_display = entry.display.clone();
                }
                drop(g);
                st.emit(AppEvent::State(Box::new(st.snapshot())));
            }
            UiCommand::BenchmarkModel { repo } => {
                // Dedupe — if a benchmark is already running for this
                // repo, drop the new request.
                if st
                    .snapshot()
                    .benchmarking
                    .as_deref()
                    .is_some_and(|r| r == repo)
                {
                    continue;
                }
                // Only benchmark downloaded repos — the script will
                // fail otherwise, but we surface a friendlier error.
                if !st.snapshot().downloaded_models.contains(&repo) {
                    st.emit(AppEvent::Info {
                        msg: format!("Download {} first, then test speed.", repo),
                    });
                    continue;
                }
                let st_inner = st.clone();
                let repo_clone = repo.clone();
                tokio::spawn(async move {
                    // Mark as benchmarking so the UI shows a spinner
                    // and disables duplicate Test clicks.
                    {
                        let mut g = st_inner.inner.lock();
                        g.pub_state.benchmarking = Some(repo_clone.clone());
                        drop(g);
                        st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                    }
                    let res = benchmark::benchmark_chat_model(&repo_clone).await;
                    let mut g = st_inner.inner.lock();
                    g.pub_state.benchmarking = None;
                    match res {
                        Ok(speed) => {
                            g.pub_state.model_speeds.insert(repo_clone.clone(), speed.clone());
                            drop(g);
                            st_inner.emit(AppEvent::Ok {
                                msg: format!("Speed: {} — {}", repo_clone, speed),
                            });
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                        Err(e) => {
                            drop(g);
                            st_inner.emit(AppEvent::Error {
                                msg: format!("Speed test failed for {}: {}", repo_clone, e),
                            });
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                    }
                });
            }
            UiCommand::DownloadWhisperModel { repo } => {
                {
                    let g = active.lock();
                    if g.contains_key(&repo) {
                        continue;
                    }
                }
                let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel::<()>();
                cancel_handles.lock().insert(repo.clone(), cancel_tx);

                let st_inner = st.clone();
                let repo_clone = repo.clone();
                let active_inner = Arc::clone(&active);
                let cancel_inner = Arc::clone(&cancel_handles);
                let handle = tokio::spawn(async move {
                    {
                        let mut g = st_inner.inner.lock();
                        g.pub_state.downloading_wmodel = Some(repo_clone.clone());
                        g.pub_state.wmodel_download_progress = 0.0;
                        drop(g);
                        st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                    }
                    let res = mlx_models::download_model(&repo_clone, cancel_rx).await;
                    let outcome: DownloadOutcome = match res {
                        Ok((mut progress_rx, done_rx)) => {
                            let mut done_rx = std::pin::pin!(done_rx);
                            loop {
                                tokio::select! {
                                    biased;
                                    pct = progress_rx.recv() => {
                                        if let Some(p) = pct {
                                            let mut g = st_inner.inner.lock();
                                            if g.pub_state.downloading_wmodel.as_deref() == Some(&repo_clone) {
                                                g.pub_state.wmodel_download_progress = p;
                                                drop(g);
                                                st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                                            }
                                        } else {
                                            break loop_finish(&mut done_rx).await;
                                        }
                                    }
                                    result = &mut done_rx => {
                                        break match result {
                                            Ok(o) => o,
                                            Err(_) => DownloadOutcome::Failed(anyhow::anyhow!(
                                                "download task ended without reporting outcome"
                                            )),
                                        };
                                    }
                                }
                            }
                        }
                        Err(e) => DownloadOutcome::Failed(e),
                    };

                    match outcome {
                        DownloadOutcome::Completed => {
                            log::info!("whisper download complete: {repo_clone}");
                            // Whisper-only scan — mirror of the LLM
                            // download path. Without this filter a
                            // freshly-downloaded STT model would also
                            // pollute the LLM dropdown.
                            let scanned = mlx_models::scan_downloaded_whispers();
                            let mut downloaded: Vec<String> =
                                scanned.iter().map(|(r, _)| r.clone()).collect();
                            downloaded.sort();
                            let mut g = st_inner.inner.lock();
                            g.pub_state.downloaded_wmodels = downloaded;
                            g.pub_state.downloaded_sizes.clear();
                            for (repo, bytes) in scanned {
                                g.pub_state.downloaded_sizes.insert(repo, bytes);
                            }
                            g.pub_state.downloading_wmodel = None;
                            g.pub_state.wmodel_download_progress = 0.0;
                            drop(g);
                            st_inner.emit(AppEvent::Ok {
                                msg: format!("✓ Downloaded STT model {}", repo_clone),
                            });
                            st_inner.emit(AppEvent::DownloadedModelsChanged);
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                        DownloadOutcome::Cancelled => {
                            log::info!("whisper download cancelled: {repo_clone}");
                            let mut g = st_inner.inner.lock();
                            g.pub_state.downloading_wmodel = None;
                            g.pub_state.wmodel_download_progress = 0.0;
                            drop(g);
                            st_inner.emit(AppEvent::Info {
                                msg: format!("Cancelled download of STT {}", repo_clone),
                            });
                            st_inner.emit(AppEvent::DownloadedModelsChanged);
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                        DownloadOutcome::Failed(e) => {
                            log::warn!("whisper download failed: {e}");
                            let mut g = st_inner.inner.lock();
                            g.pub_state.downloading_wmodel = None;
                            g.pub_state.wmodel_download_progress = 0.0;
                            drop(g);
                            st_inner.emit(AppEvent::Error {
                                msg: format!("STT download failed: {e}"),
                            });
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                    }

                    active_inner.lock().remove(&repo_clone);
                    cancel_inner.lock().remove(&repo_clone);
                });
                active.lock().insert(repo, handle);
            }
            UiCommand::CancelWhisperDownload { repo } => {
                if let Some(tx) = cancel_handles.lock().remove(&repo) {
                    let _ = tx.send(());
                }
            }
            UiCommand::DeleteWhisperModel { repo } => {
                match mlx_models::delete_model(&repo) {
                    Ok(true) => {
                        // Whisper-only scan — same rationale as the
                        // LLM delete handler above.
                        let scanned = mlx_models::scan_downloaded_whispers();
                        let mut downloaded: Vec<String> =
                            scanned.iter().map(|(r, _)| r.clone()).collect();
                        downloaded.sort();
                        let mut g = st.inner.lock();
                        g.pub_state.downloaded_wmodels = downloaded;
                        g.pub_state.downloaded_sizes.remove(&repo);
                        if g.pub_state.wmodel == repo {
                            g.pub_state.wmodel = String::new();
                            g.pub_state.wmodel_display = String::new();
                        }
                        drop(g);
                        st.emit(AppEvent::Ok { msg: format!("Deleted STT {}", repo) });
                        st.emit(AppEvent::DownloadedModelsChanged);
                        st.emit(AppEvent::State(Box::new(st.snapshot())));
                    }
                    Ok(false) => {
                        st.emit(AppEvent::Info { msg: format!("{} was not in cache", repo) });
                    }
                    Err(e) => {
                        st.emit(AppEvent::Error { msg: format!("Delete failed: {e}") });
                    }
                }
            }
            UiCommand::UseWhisperModel { repo } => {
                let mut g = st.inner.lock();
                g.pub_state.wmodel = repo.clone();
                if let Some(entry) = g.pub_state.wmodels.iter().find(|m| m.repo == repo) {
                    g.pub_state.wmodel_display = entry.display.clone();
                }
                drop(g);
                st.emit(AppEvent::State(Box::new(st.snapshot())));
            }
            UiCommand::BenchmarkWhisperModel { repo } => {
                if st
                    .snapshot()
                    .wmodel_benchmarking
                    .as_deref()
                    .is_some_and(|r| r == repo)
                {
                    continue;
                }
                if !st.snapshot().downloaded_wmodels.contains(&repo) {
                    st.emit(AppEvent::Info {
                        msg: format!("Download {} first, then test speed.", repo),
                    });
                    continue;
                }
                let st_inner = st.clone();
                let repo_clone = repo.clone();
                tokio::spawn(async move {
                    {
                        let mut g = st_inner.inner.lock();
                        g.pub_state.wmodel_benchmarking = Some(repo_clone.clone());
                        drop(g);
                        st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                    }
                    let res = benchmark::benchmark_whisper_model(&repo_clone).await;
                    let mut g = st_inner.inner.lock();
                    g.pub_state.wmodel_benchmarking = None;
                    match res {
                        Ok(speed) => {
                            g.pub_state.wmodel_speeds.insert(repo_clone.clone(), speed.clone());
                            drop(g);
                            st_inner.emit(AppEvent::Ok {
                                msg: format!("Speed: {} — {}", repo_clone, speed),
                            });
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                        Err(e) => {
                            drop(g);
                            st_inner.emit(AppEvent::Error {
                                msg: format!("Speed test failed for {}: {}", repo_clone, e),
                            });
                            st_inner.emit(AppEvent::State(Box::new(st_inner.snapshot())));
                        }
                    }
                });
            }
        }
    }

    // Drain any still-running downloads on shutdown so the tasks don't
    // get dropped mid-flight.
    let drained: Vec<_> = active.lock().drain().map(|(_, h)| h).collect();
    for h in drained {
        let _ = h.await;
    }
}

/// Helper for the download driver: when the progress channel closes
/// before `done_rx` fires (e.g. child stderr EOF with no final send),
/// await `done_rx` and turn the terminal outcome into something we can
/// `break` out of the select loop with. Takes a pinned reference so the
/// caller can keep using the same receiver in the outer select! loop
/// without re-creating it.
async fn loop_finish(
    done_rx: &mut std::pin::Pin<&mut tokio::sync::oneshot::Receiver<
        crate::llm::mlx_models::DownloadOutcome,
    >>,
) -> crate::llm::mlx_models::DownloadOutcome {
    match done_rx.await {
        Ok(o) => o,
        Err(_) => crate::llm::mlx_models::DownloadOutcome::Failed(anyhow::anyhow!(
            "download task ended without reporting outcome"
        )),
    }
}

pub fn launch_desktop() {
    let config = Config::default()
        .with_window(
            WindowBuilder::new()
                .with_title("Foundry — Realtime Voice Intelligence")
                .with_inner_size(LogicalSize::new(1280.0, 820.0))
                .with_min_inner_size(LogicalSize::new(900.0, 600.0))
                .with_resizable(true),
        )
        .with_custom_head(
            r#"<style>
                html, body { background: #08080B; color: #F5F5F8; }
            </style>"#
                .to_string(),
        );

    LaunchBuilder::desktop()
        .with_cfg(config)
        .launch(Root);
}

#[component]
fn Root() -> Element {
    let app_state = use_context_provider(|| AppState::new(detect_backends()));

    let latest = use_signal(|| app_state.snapshot());
    let level = use_signal(|| 0.0_f32);
    let toast = use_signal(|| None::<ToastInfo>);
    let show_models = use_signal(|| false);
    let show_drawer = use_signal(|| false);

    // Subscribe to events from the AppState broadcast channel.
    {
        let st = app_state.clone();
        use_future(move || {
            let st = st.clone();
            let mut latest = latest;
            let mut level = level;
            let mut toast = toast;
            async move {
                let mut rx = st.events.subscribe();
                while let Ok(ev) = rx.recv().await {
                    match ev {
                        AppEvent::State(s) => latest.set(*s),
                        AppEvent::Level { v } => level.set(v),
                        AppEvent::Info { msg } if !msg.is_empty() => {
                            toast.set(Some(ToastInfo { kind: ToastKind::Info, msg }));
                            let mut t = toast;
                            spawn(async move {
                                tokio::time::sleep(Duration::from_secs(4)).await;
                                t.set(None);
                            });
                        }
                        AppEvent::Ok { msg } => {
                            toast.set(Some(ToastInfo { kind: ToastKind::Ok, msg }));
                            let mut t = toast;
                            spawn(async move {
                                tokio::time::sleep(Duration::from_secs(4)).await;
                                t.set(None);
                            });
                        }
                        AppEvent::Error { msg } => {
                            toast.set(Some(ToastInfo { kind: ToastKind::Error, msg }));
                            let mut t = toast;
                            spawn(async move {
                                tokio::time::sleep(Duration::from_secs(8)).await;
                                t.set(None);
                            });
                        }
                        AppEvent::Transcript(_) => {}
                        _ => {}
                    }
                }
            }
        });
    }

    // Boot — devices + models.
    {
        let st = app_state.clone();
        use_future(move || {
            let st = st.clone();
            async move {
                // Detect host device (chip, RAM, cores, OS) once at
                // startup. The Models modal renders a small "Device"
                // card with these. Best-effort: failures produce a
                // partial struct, never a hard error.
                {
                    let specs = crate::system::detect_device();
                    log::info!(
                        "device: {} ({} GB RAM, {} physical / {} logical cores, macOS {}, apple_silicon={})",
                        specs.chip_short,
                        specs.total_memory_bytes / (1024 * 1024 * 1024),
                        specs.physical_cpus,
                        specs.logical_cpus,
                        specs.os_version,
                        specs.is_apple_silicon,
                    );
                    let mut g = st.inner.lock();
                    g.pub_state.host = Some(specs);
                    drop(g);
                    st.emit(AppEvent::State(Box::new(st.snapshot())));
                }

                // Build the device list: cpal input devices + (on macOS) the
                // ScreenCaptureKit "System Audio" pseudo-device at the top.
                let mut devices: Vec<crate::state::DeviceInfo> = match list_input_devices() {
                    Ok(devs) => devs
                        .iter()
                        .map(|d| crate::state::DeviceInfo {
                            index: d.index,
                            name: d.name.clone(),
                            channels: d.channels,
                            sample_rate: d.sample_rate,
                        })
                        .collect(),
                    Err(e) => {
                        st.emit(AppEvent::Error {
                            msg: format!("Failed to list audio devices: {e}"),
                        });
                        Vec::new()
                    }
                };
                if cfg!(target_os = "macos") {
                    // Prepend the SCK pseudo-device so it appears at the top
                    // of the dropdown. Index -1 signals "not a cpal device".
                    // The `name` field stays the raw internal key (so the
                    // pipeline can still match on it), but the user sees
                    // the friendlier label through the `display` field in
                    // the toolbar (see `components/toolbar.rs`).
                    devices.insert(
                        0,
                        crate::state::DeviceInfo {
                            index: -1,
                            name: crate::audio::SYSTEM_AUDIO_DEVICE.to_string(),
                            channels: 2,
                            sample_rate: 48_000.0,
                        },
                    );
                }

                // Default device selection — ALWAYS pick System Audio
                // (ScreenCaptureKit) on every launch, ignoring any prior
                // selection. Rationale: a Mac user opening Foundry
                // almost always wants "what's playing on my speakers",
                // and a wrong default (e.g. "Steam Streaming Speakers",
                // a Steam Link virtual output that doesn't loopback)
                // silently captures nothing. The user can still pick
                // something else from the dropdown; we just refuse to
                // re-default them onto a non-SCK device every session.
                //   1. System Audio (ScreenCaptureKit) if available
                //   2. BlackHole 2ch
                //   3. First cpal input
                {
                    let mut g = st.inner.lock();
                    g.pub_state.devices = devices;
                    g.pub_state.device = g
                        .pub_state
                        .devices
                        .iter()
                        .find(|d| d.name == crate::audio::SYSTEM_AUDIO_DEVICE)
                        .map(|d| d.name.clone())
                        .or_else(|| {
                            g.pub_state
                                .devices
                                .iter()
                                .find(|d| d.name.to_lowercase().contains("blackhole"))
                                .map(|d| d.name.clone())
                        })
                        .or_else(|| g.pub_state.devices.first().map(|d| d.name.clone()))
                        .unwrap_or_default();
                    drop(g);
                    st.emit(AppEvent::State(Box::new(st.snapshot())));
                }

                // Output device list — populates the "Output" dropdown
                // in the toolbar. The pipeline reads `state.output_device`
                // before opening the SCK capture and switches the system
                // default output if it differs from the current one.
                #[cfg(target_os = "macos")]
                {
                    let st_o = st.clone();
                    spawn(async move {
                        let devs = crate::audio::output::list_output_devices().unwrap_or_default();
                        let entries: Vec<crate::state::DeviceInfo> = devs
                            .into_iter()
                            .enumerate()
                            .map(|(i, d)| crate::state::DeviceInfo {
                                index: i as i32,
                                name: d.name,
                                channels: 2, // not used for output; UI doesn't display it
                                sample_rate: 0.0,
                            })
                            .collect();
                        let mut g = st_o.inner.lock();
                        g.pub_state.output_devices = entries;
                        drop(g);
                        st_o.emit(AppEvent::State(Box::new(st_o.snapshot())));
                    });
                }

                // MLX translation model list — fetched live from
                // `mlx-community` on HuggingFace. Falls back to a curated
                // list if both the API and the on-disk cache are unavailable.
                //
                // We surface the dropdown immediately (with the fallback list
                // if the API is slow) and update it as soon as the fetch
                // completes.
                let mlx_ok = st.snapshot().backends.mlx_lm_available;
                if !mlx_ok {
                    st.emit(AppEvent::Error {
                        msg: "mlx-lm not detected — pip install mlx-lm into the project .venv".into(),
                    });
                } else {
                    // Seed the dropdown with the fallback list so the UI is
                    // usable before the API responds. The fetch updates it
                    // in place below.
                    let fallback: Vec<MlxModel> = mlx_models::fallback_models();
                    {
                        let mut g = st.inner.lock();
                        g.pub_state.models = fallback
                            .iter()
                            .map(|m| MlxModelEntry {
                                repo: m.repo.clone(),
                                display: m.display.clone(),
                                quant: m.quant.clone(),
                            })
                            .collect();
                        // Defensive: if the user previously had a
                        // Whisper STT model selected as their chat
                        // model (a leftover from the bug where
                        // `downloaded_models` and `downloaded_wmodels`
                        // shared the full HF cache), the value is no
                        // longer in `models` and would render as
                        // "missing" in the dropdown. Drop it so the
                        // next block can pick a clean default.
                        if !g.pub_state.model.is_empty()
                            && !g.pub_state.models.iter().any(|m| m.repo == g.pub_state.model)
                        {
                            g.pub_state.model = String::new();
                            g.pub_state.model_display = String::new();
                        }
                        // Default-select the first model if nothing is set.
                        if g.pub_state.model.is_empty() {
                            if let Some(first) = g.pub_state.models.first().cloned() {
                                g.pub_state.model = first.repo;
                                g.pub_state.model_display = first.display;
                            }
                        }
                        drop(g);
                        st.emit(AppEvent::State(Box::new(st.snapshot())));
                    }

                    // Now hit HuggingFace for the real list.
                    let st2 = st.clone();
                    spawn(async move {
                        let fetched = mlx_models::fetch_mlx_models(false).await;
                        match fetched {
                            Ok(models) if !models.is_empty() => {
                                // Extract catalog sizes up-front so we
                                // can populate `catalog_sizes` in the
                                // same state update that swaps in the
                                // new catalog list.
                                let sizes: Vec<(String, u64)> = models
                                    .iter()
                                    .filter_map(|m| m.size_bytes.map(|b| (m.repo.clone(), b)))
                                    .collect();
                                let entries: Vec<MlxModelEntry> = models
                                    .iter()
                                    .map(|m| MlxModelEntry {
                                        repo: m.repo.clone(),
                                        display: m.display.clone(),
                                        quant: m.quant.clone(),
                                    })
                                    .collect();
                                {
                                    let mut g = st2.inner.lock();
                                    g.pub_state.models = entries;
                                    g.pub_state.models_loaded = true;
                                    // Merge catalog sizes — keep any
                                    // pre-existing keys for repos the
                                    // new catalog dropped.
                                    for (repo, bytes) in sizes {
                                        g.pub_state.catalog_sizes.insert(repo, bytes);
                                    }
                                    // If the current model isn't in the new
                                    // list, fall back to the first one.
                                    let still_present = g
                                        .pub_state
                                        .models
                                        .iter()
                                        .any(|m| m.repo == g.pub_state.model);
                                    if !still_present {
                                        if let Some(first) = g.pub_state.models.first().cloned() {
                                            g.pub_state.model = first.repo;
                                            g.pub_state.model_display = first.display;
                                        }
                                    } else {
                                        // Refresh the display name in case
                                        // the friendly form changed.
                                        if let Some(m) = g
                                            .pub_state
                                            .models
                                            .iter()
                                            .find(|m| m.repo == g.pub_state.model)
                                            .cloned()
                                        {
                                            g.pub_state.model_display = m.display;
                                        }
                                    }
                                    log::info!(
                                        "HF: loaded {} MLX models from mlx-community (first: {})",
                                        models.len(),
                                        models.first().map(|m| m.repo.as_str()).unwrap_or("?")
                                    );
                                    drop(g);
                                    st2.emit(AppEvent::Info {
                                        msg: format!(
                                            "✓ Loaded {} MLX models from HuggingFace (mlx-community)",
                                            models.len()
                                        ),
                                    });
                                    st2.emit(AppEvent::State(Box::new(st2.snapshot())));
                                }

                                // ── Background: fetch on-disk size for
                                // every catalog repo. The HF models
                                // listing no longer carries file sizes
                                // in `siblings[]`; we have to hit the
                                // tree endpoint per repo. Result is
                                // streamed into `state.catalog_sizes`
                                // one repo at a time so the UI's
                                // "≈ X GB [Fits]" chip pops in as
                                // each fetch completes (instead of
                                // waiting for the full sweep).
                                {
                                    let st3 = st2.clone();
                                    // `models` is still in scope — the
                                    // earlier `.iter().map(...).collect()`
                                    // calls only borrowed it. We clone
                                    // the repo ids out before the task
                                    // moves on.
                                    let repos: Vec<String> = models
                                        .iter()
                                        .map(|m| m.repo.clone())
                                        .collect();
                                    spawn(async move {
                                        log::info!(
                                            "prefetching on-disk sizes for {} repos (5 concurrent)",
                                            repos.len()
                                        );
                                        let st_clone = st3.clone();
                                        mlx_models::prefetch_repo_sizes(
                                            repos,
                                            move |repo, bytes| {
                                                {
                                                    let mut g = st_clone.inner.lock();
                                                    match bytes {
                                                        Some(b) => {
                                                            g.pub_state
                                                                .catalog_sizes
                                                                .insert(repo.clone(), b);
                                                        }
                                                        None => {
                                                            // Don't remove a
                                                            // previously-cached
                                                            // good value if
                                                            // this attempt
                                                            // transiently
                                                            // failed; the
                                                            // current sweep is
                                                            // best-effort.
                                                        }
                                                    }
                                                }
                                                st_clone.emit(AppEvent::State(Box::new(
                                                    st_clone.snapshot(),
                                                )));
                                            },
                                        )
                                        .await;
                                        log::info!("repo-size prefetch complete");
                                    });
                                }
                            }
                            Ok(_) => {
                                log::warn!("HF API returned empty list");
                            }
                            Err(e) => {
                                log::warn!("HF API fetch failed: {e}");
                                // Try the stale cache as a last resort.
                                if let Some(stale) = mlx_models::read_stale_cache() {
                                    let entries: Vec<MlxModelEntry> = stale
                                        .iter()
                                        .map(|m| MlxModelEntry {
                                            repo: m.repo.clone(),
                                            display: m.display.clone(),
                                            quant: m.quant.clone(),
                                        })
                                        .collect();
                                    log::info!(
                                        "using stale cache: {} MLX models",
                                        entries.len()
                                    );
                                    let mut g = st2.inner.lock();
                                    g.pub_state.models = entries;
                                    g.pub_state.models_loaded = true;
                                    drop(g);
                                    st2.emit(AppEvent::Info {
                                        msg: format!(
                                            "⚠ Using cached model list (HF API unreachable: {})",
                                            e
                                        ),
                                    });
                                    st2.emit(AppEvent::State(Box::new(st2.snapshot())));
                                } else {
                                    st2.emit(AppEvent::Error {
                                        msg: format!("HF model fetch failed: {e}"),
                                    });
                                }
                            }
                        }
                    });

                    // Initial scan of the local HF cache — populates
                    // `downloaded_models` AND `downloaded_sizes` (bytes
                    // per repo, walked from the `blobs/` subdir). Runs in
                    // parallel with the HF API fetch above (HF API goes
                    // over the network, this is local fs work).
                    let st3 = st.clone();
                    spawn(async move {
                        // Split the cache into LLM and Whisper up-front.
                        // Previously we mirrored the same full list into
                        // both `downloaded_models` and `downloaded_wmodels`
                        // and relied on render-time filtering — but the
                        // synthetic-entry fallback in the toolbar's
                        // `ModelDropdown` would still surface a Whisper
                        // repo (e.g. "Whisper Large V3 Turbo") as a
                        // chat-model option. Filtering at scan time
                        // makes the two lists strictly disjoint.
                        let llm_scanned = mlx_models::scan_downloaded_llms();
                        let whisper_scanned = mlx_models::scan_downloaded_whispers();
                        let mut llm_downloaded: Vec<String> =
                            llm_scanned.iter().map(|(r, _)| r.clone()).collect();
                        let mut whisper_downloaded: Vec<String> =
                            whisper_scanned.iter().map(|(r, _)| r.clone()).collect();
                        llm_downloaded.sort();
                        whisper_downloaded.sort();
                        log::info!(
                            "scanned HF cache: {} LLM + {} Whisper repos",
                            llm_downloaded.len(),
                            whisper_downloaded.len()
                        );
                        {
                            let mut g = st3.inner.lock();
                            g.pub_state.downloaded_models = llm_downloaded;
                            g.pub_state.downloaded_wmodels = whisper_downloaded;
                            g.pub_state.downloaded_sizes.clear();
                            for (repo, bytes) in llm_scanned.into_iter().chain(whisper_scanned) {
                                g.pub_state.downloaded_sizes.insert(repo, bytes);
                            }
                            drop(g);
                            st3.emit(AppEvent::State(Box::new(st3.snapshot())));
                        }
                    });

                    // Fetch the MLX-Whisper catalog.
                    let st4 = st.clone();
                    spawn(async move {
                        let res = mlx_models::fetch_whisper_models(false).await;
                        match res {
                            Ok(models) if !models.is_empty() => {
                                let sizes: Vec<(String, u64)> = models
                                    .iter()
                                    .filter_map(|m| m.size_bytes.map(|b| (m.repo.clone(), b)))
                                    .collect();
                                let entries: Vec<crate::state::MlxModelEntry> = models
                                    .iter()
                                    .map(|m| crate::state::MlxModelEntry {
                                        repo: m.repo.clone(),
                                        display: m.display.clone(),
                                        // Whisper models are always
                                        // distributed in a fixed
                                        // precision (fp16) and we
                                        // don't surface it as a
                                        // quantization choice in the
                                        // UI, so leave the field
                                        // empty and let the VRAM
                                        // estimator use the default
                                        // overhead.
                                        quant: None,
                                    })
                                    .collect();
                                log::info!(
                                    "HF: loaded {} MLX-Whisper models",
                                    entries.len()
                                );
                                let mut g = st4.inner.lock();
                                g.pub_state.wmodels = entries;
                                g.pub_state.wmodels_loaded = true;
                                // Mirror of the LLM defensive guard:
                                // clear `wmodel` if the prior selection
                                // isn't in the freshly-loaded Whisper
                                // catalog (e.g. a leftover from the
                                // shared-cache bug where a chat model
                                // could land in `downloaded_wmodels`).
                                if !g.pub_state.wmodel.is_empty()
                                    && !g.pub_state.wmodels.iter().any(|m| m.repo == g.pub_state.wmodel)
                                {
                                    g.pub_state.wmodel = String::new();
                                    g.pub_state.wmodel_display = String::new();
                                }
                                for (repo, bytes) in sizes {
                                    g.pub_state.catalog_sizes.insert(repo, bytes);
                                }
                                drop(g);
                                st4.emit(AppEvent::State(Box::new(st4.snapshot())));
                            }
                            Ok(_) => log::warn!("HF returned empty Whisper list"),
                            Err(e) => {
                                log::warn!("HF Whisper fetch failed: {e}");
                                // Last-resort fallback list.
                                let entries: Vec<crate::state::MlxModelEntry> =
                                    mlx_models::fallback_whisper_models()
                                        .into_iter()
                                        .map(|m| crate::state::MlxModelEntry {
                                            repo: m.repo,
                                            display: m.display,
                                            // Whisper repos are always
                                            // distributed in a fixed
                                            // precision (typically
                                            // fp16), but we don't try
                                            // to parse it from the name.
                                            quant: None,
                                        })
                                        .collect();
                                let mut g = st4.inner.lock();
                                g.pub_state.wmodels = entries;
                                g.pub_state.wmodels_loaded = true;
                                // Same defensive guard as the API path.
                                if !g.pub_state.wmodel.is_empty()
                                    && !g.pub_state.wmodels.iter().any(|m| m.repo == g.pub_state.wmodel)
                                {
                                    g.pub_state.wmodel = String::new();
                                    g.pub_state.wmodel_display = String::new();
                                }
                                drop(g);
                                st4.emit(AppEvent::State(Box::new(st4.snapshot())));
                            }
                        }
                    });
                }
            }
        });
    }

    // (Download / delete / use-model actions are handled by the
    // `run_command_driver` task spawned at the top of `Root`.)

    // Boot audio pipeline + STT + LLM loop.
    {
        let st = app_state.clone();
        use_future(move || {
            let st = st.clone();
            async move {
                let audio = pipeline::spawn(st.clone());
                let chunks = audio.chunks.clone();
                let stt_st = st.clone();
                spawn(async move {
                    while let Ok(chunk) = chunks.recv().await {
                        if !stt_st.snapshot().listening {
                            continue;
                        }
                        let snap = stt_st.snapshot();
                        let src_lang = snap.src_lang.clone();
                        let res = crate::stt::transcribe(stt_st.clone(), chunk, &src_lang).await;
                        if let Some(r) = res {
                            if r.text.is_empty() {
                                continue;
                            }
                            let l = stt_st.snapshot();
                            if l.model.is_empty() {
                                continue;
                            }
                            let _ = crate::llm::translate(
                                stt_st.clone(),
                                r.text,
                                src_lang,
                                l.tgt_lang.clone(),
                                l.model.clone(),
                            )
                            .await;
                        }
                    }
                });

                loop {
                    if *audio.stop.borrow() {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(500)).await;
                }
            }
        });
    }

    let s = latest();
    let lvl = level();
    let app_state_for_render = app_state.clone();
    let mut show_models = show_models;
    let mut show_drawer = show_drawer;

    rsx! {
        style { "{crate::components::ROOT_STYLE}" }
        div { class: "app",
            Header {
                state: s.clone(),
                on_models: move |_| show_models.set(true),
                on_drawer: move |_| show_drawer.set(true),
            }
            Toolbar {
                state: s.clone(),
                on_change: {
                    let st = app_state_for_render.clone();
                    move |patch: serde_json::Value| {
                        if patch.get("open_models").and_then(|x| x.as_bool()) == Some(true) {
                            show_models.set(true);
                            return;
                        }
                        st.apply_control(patch)
                    }
                },
            }
            main { Feed {
                state: s.clone(),
                on_change: {
                    let st = app_state_for_render.clone();
                    move |patch: serde_json::Value| st.apply_control(patch)
                },
            } }
            StatsBar {
                level: lvl,
                state: s.clone(),
            }
            Footer { state: s.clone() }
            if show_models() {
                ModelsModal {
                    state: s.clone(),
                    on_close: move |_| show_models.set(false),
                }
            }
            if show_drawer() {
                Drawer {
                    state: s.clone(),
                    on_close: move |_| show_drawer.set(false),
                    on_save: {
                        let st = app_state_for_render.clone();
                        move |patch: serde_json::Value| {
                            st.apply_control(patch);
                            show_drawer.set(false);
                        }
                    },
                }
            }
            if let Some(t) = toast() {
                Toast { info: t }
            }
        }
    }
}

#[derive(Clone, PartialEq)]
struct ToastInfo {
    kind: ToastKind,
    msg: String,
}

#[derive(Clone, Copy, PartialEq)]
enum ToastKind {
    Info,
    Ok,
    Error,
}

#[component]
fn Toast(info: ToastInfo) -> Element {
    let class = match info.kind {
        ToastKind::Info => "toast",
        ToastKind::Ok => "toast ok",
        ToastKind::Error => "toast err",
    };
    rsx! {
        div { class: "{class}", "{info.msg}" }
    }
}

#[component]
fn Header(
    state: PublicState,
    on_models: EventHandler<()>,
    on_drawer: EventHandler<()>,
) -> Element {
    let header_class = if state.listening { "recording" } else { "" };
    rsx! {
        header { class: "{header_class}",
            div { class: "brand",
                div { class: "brand-mark",
                    svg { width: "22", height: "22", view_box: "0 0 32 32",
                        path {
                            d: "M10 7v18M10 7h11M10 16h8",
                            stroke: "white",
                            stroke_width: "3",
                            stroke_linecap: "square",
                            fill: "none",
                        }
                    }
                }
                div { class: "brand-text",
                    div { class: "brand-name", "Foundry" }
                    div { class: "brand-tag", "Realtime · STT → Translate · by ",
                        b { "The Factory Group" }
                    }
                }
            }
            div { class: "header-spacer" }
            StatusPill { state: state.clone() }
            button {
                class: "icon-btn",
                title: "Models",
                onclick: move |_| on_models.call(()),
                svg { view_box: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: "2",
                    path { d: "M12 2 L2 7 L12 12 L22 7 L12 2 Z" }
                    path { d: "M2 17 L12 22 L22 17" }
                    path { d: "M2 12 L12 17 L22 12" }
                }
            }
            button {
                class: "icon-btn",
                title: "Settings",
                onclick: move |_| on_drawer.call(()),
                svg { view_box: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: "2",
                    circle { cx: "12", cy: "12", r: "3" }
                    path { d: "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" }
                }
            }
        }
    }
}

#[component]
fn StatsBar(level: f32, state: PublicState) -> Element {
    let bars: Vec<f32> = (0..64)
        .map(|i| {
            let phase = (i as f32 / 64.0) * std::f32::consts::PI * 4.0;
            let base = (phase.sin() + 1.0) * 0.5;
            base * level.max(0.05)
        })
        .collect();

    rsx! {
        div { class: "stats-bar",
            Waveform { level, bars }
            div { class: "stat-pill",
                span { class: "l", "STT" }
                span { class: "v",
                    if state.stt_busy { "🎙 busy" } else { "idle" }
                }
            }
            div { class: "stat-pill",
                span { class: "l", "LLM" }
                span { class: "v",
                    if state.llm_busy { "⚡ busy" } else { "idle" }
                }
            }
            div { class: "stat-pill ok",
                span { class: "l", "Segments" }
                span { class: "v", "{state.history.len()}" }
            }
        }
    }
}