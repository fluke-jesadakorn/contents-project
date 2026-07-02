//! Models modal — full HuggingFace catalogs for MLX-LM and MLX-Whisper,
//! with download / use / delete actions. The toolbar dropdowns only show
//! downloaded models; this modal is where the user picks what to download.

use crate::llm::mlx_models;
use crate::state::{AppEvent, AppState, MlxModelEntry, PublicState, UiCommand};
use crate::system::{
    estimate_vram_bytes, fit_status, format_bytes, FitStatus,
};
use dioxus::prelude::*;

#[component]
pub fn ModelsModal(state: PublicState, on_close: EventHandler<()>) -> Element {
    let mut tab = use_signal(|| "mlx".to_string());
    let custom_repo = use_signal(String::new);
    let refreshing = use_signal(|| false);

    rsx! {
        div {
            class: "modal-bg",
            style: "display: flex;",
            onclick: move |_| on_close.call(()),
            div {
                class: "modal",
                onclick: move |e| e.stop_propagation(),
                div { class: "modal-head",
                    h2 { "Models",
                        small { "Pick what to download — only downloaded models appear in the toolbar" }
                    }
                    button { class: "modal-close", onclick: move |_| on_close.call(()), "×" }
                }
                div { class: "modal-tabs",
                    TabBtn {
                        label: "MLX chat".to_string(),
                        active: tab() == "mlx",
                        on_click: move |_| tab.set("mlx".to_string()),
                    }
                    TabBtn {
                        label: "MLX-Whisper (STT)".to_string(),
                        active: tab() == "whisper",
                        on_click: move |_| tab.set("whisper".to_string()),
                    }
                }
                div { class: "modal-body",
                    if tab() == "mlx" {
                        MlxTab {
                            state: state.clone(),
                            custom_repo: custom_repo,
                            refreshing: refreshing,
                        }
                    } else {
                        WhisperTab {
                            state: state.clone(),
                            custom_repo: custom_repo,
                            refreshing: refreshing,
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn TabBtn(label: String, active: bool, on_click: EventHandler<()>) -> Element {
    let class = if active { "active" } else { "" };
    rsx! {
        button { class: "{class}", onclick: move |_| on_click.call(()), "{label}" }
    }
}

/// "Device" card pinned at the top of every Models tab. Shows the
/// chip, total RAM, core counts, OS, and a flag for whether MLX will
/// actually work on this machine. Hidden when detection failed (so we
/// don't render an empty box on unsupported hosts).
#[component]
fn DeviceCard(state: PublicState) -> Element {
    let Some(specs) = state.host.clone() else {
        return rsx! { div {} };
    };
    let ram_gb = specs.total_memory_bytes as f64 / (1024.0 * 1024.0 * 1024.0);
    let cores_label = if specs.physical_cpus > 0 && specs.logical_cpus > specs.physical_cpus {
        format!("{}p / {}e cores", specs.physical_cpus, specs.logical_cpus)
    } else if specs.physical_cpus > 0 {
        format!("{} cores", specs.physical_cpus)
    } else {
        String::new()
    };
    let mlx_ready = specs.is_apple_silicon;
    rsx! {
        div { class: "device-card",
            div { class: "device-card-head",
                div { class: "device-card-icon",
                    if mlx_ready { "⚙" } else { "⚠" }
                }
                div { class: "device-card-body",
                    div { class: "device-card-name", "{specs.chip_short}" }
                    div { class: "device-card-sub",
                        "{ram_gb:.0} GB · "
                        "{cores_label} · "
                        "macOS {specs.os_version}"
                    }
                }
                div {
                    class: if mlx_ready { "device-card-flag ok" } else { "device-card-flag warn" },
                    if mlx_ready { "MLX ready" } else { "MLX unsupported" }
                }
            }
            if !mlx_ready {
                div { class: "device-card-warn",
                    "Foundry's MLX translation and STT only run on Apple Silicon (M1/M2/M3/M4). Intel Macs are unsupported."
                }
            }
        }
    }
}

// ─── MLX-LM tab ─────────────────────────────────────────────────────────────

#[component]
fn MlxTab(
    state: PublicState,
    custom_repo: Signal<String>,
    refreshing: Signal<bool>,
) -> Element {
    let mlx_lm_ok = state.backends.mlx_lm_available;
    let total = state.models.len();
    let downloaded_count = state.downloaded_models.len();

    rsx! {
        div {
            DeviceCard { state: state.clone() }
            div { class: "status-strip",
                span { class: "status-pill-inline",
                    if mlx_lm_ok { "mlx-lm: ✓" } else { "mlx-lm: ✗ (pip install mlx-lm)" }
                }
                span { class: "status-pill-inline",
                    if state.models_loaded {
                        "HuggingFace: mlx-community ✓"
                    } else if total > 0 {
                        "Loading from HuggingFace…"
                    } else {
                        "HuggingFace: not loaded"
                    }
                }
                span { class: "status-pill-inline", "{downloaded_count} downloaded" }
            }
            div { class: "drawer-section",
                div { class: "drawer-head",
                    div { class: "drawer-label", "MLX chat models — HuggingFace (mlx-community)" }
                    button {
                        class: "btn-cleanup",
                        disabled: refreshing(),
                        onclick: move |_| {
                            let mut r = refreshing;
                            spawn(async move {
                                r.set(true);
                                match mlx_models::fetch_mlx_models(true).await {
                                    Ok(models) if !models.is_empty() => {
                                        let st = use_context::<AppState>();
                                        let entries: Vec<MlxModelEntry> = models
                                            .iter()
                                            .map(|m| MlxModelEntry {
                                                repo: m.repo.clone(),
                                                display: m.display.clone(),
                                                quant: m.quant.clone(),
                                            })
                                            .collect();
                                        let count = entries.len();
                                        {
                                            let mut g = st.inner.lock();
                                            g.pub_state.models = entries;
                                            g.pub_state.models_loaded = true;
                                            drop(g);
                                            st.emit(AppEvent::Ok {
                                                msg: format!("Refreshed {count} MLX chat models from HuggingFace"),
                                            });
                                            st.emit(AppEvent::State(Box::new(st.snapshot())));
                                        }
                                    }
                                    Ok(_) => {
                                        let st = use_context::<AppState>();
                                        st.emit(AppEvent::Error { msg: "HuggingFace returned no models".into() });
                                    }
                                    Err(e) => {
                                        let st = use_context::<AppState>();
                                        st.emit(AppEvent::Error {
                                            msg: format!("Refresh failed: {e}"),
                                        });
                                    }
                                }
                                r.set(false);
                            });
                        },
                        if refreshing() { "Refreshing…" } else { "Refresh from HF" }
                    }
                }
                if !mlx_lm_ok {
                    div { class: "empty-row", "Install mlx-lm into the project .venv: source .venv/bin/activate && pip install mlx-lm" }
                } else if total == 0 {
                    div { class: "empty-row", "Loading models…" }
                } else {
                    LmModelList { state: state.clone() }
                }
                div { class: "empty-row", style: "margin-top: 12px; font-size: 12px; opacity: 0.7;",
                    "Each row shows download state. Click Download to fetch (~1–4 GB per model). Models cache under ~/.cache/huggingface/hub/."
                }
            }
            div { class: "drawer-section",
                div { class: "drawer-label", "Custom HuggingFace repo" }
                div { class: "field",
                    input {
                        class: "drawer-input",
                        placeholder: "mlx-community/your-model-4bit",
                        value: "{custom_repo}",
                        oninput: move |evt| custom_repo.set(evt.value()),
                    }
                }
                div { class: "drawer-hint",
                    "Paste any mlx-community repo id (or your own). Format: org/model-name."
                }
                button {
                    class: "btn-use",
                    style: "margin-top: 8px;",
                    disabled: custom_repo().trim().is_empty(),
                    onclick: move |_| {
                        let repo = custom_repo().trim().to_string();
                        if repo.is_empty() {
                            return;
                        }
                        let st = use_context::<AppState>();
                        st.send_cmd(UiCommand::DownloadModel { repo: repo.clone() });
                        st.send_cmd(UiCommand::UseModel { repo });
                    },
                    "Download & use"
                }
            }
        }
    }
}

#[component]
fn LmModelList(state: PublicState) -> Element {
    // Build a list of catalog entries that are already downloaded.
    let mut downloaded_rows: Vec<MlxModelEntry> = state
        .models
        .iter()
        .filter(|m| state.downloaded_models.contains(&m.repo))
        .cloned()
        .collect();

    // Anything in `downloaded_models` that isn't in the catalog still
    // needs to render — a custom repo typed into the input field, or a
    // model that was in an older HF fetch and has since been removed.
    // Build a synthetic `MlxModelEntry` for it so the row still shows
    // up with Use / Delete actions.
    for repo in state.downloaded_models.iter() {
        if !state.models.iter().any(|m| &m.repo == repo) {
            downloaded_rows.push(MlxModelEntry {
                repo: repo.clone(),
                display: derive_display_from_repo(repo),
                // Custom / removed-from-catalog repos have no
                // structured quant — leave it for the VRAM
                // estimator to fall back to its default.
                quant: None,
            });
        }
    }

    let mut not_downloaded_rows: Vec<_> = state
        .models
        .iter()
        .filter(|m| !state.downloaded_models.contains(&m.repo))
        .cloned()
        .collect();

    downloaded_rows.sort_by(|a, b| a.display.cmp(&b.display));
    not_downloaded_rows.sort_by(|a, b| a.display.cmp(&b.display));

    rsx! {
        div { class: "model-list",
            div { class: "model-section-label",
                "✓ Downloaded ("
                {downloaded_rows.len().to_string()}
                ")"
            }
            for m in downloaded_rows.iter() {
                LmDownloadableRow {
                    entry: m.clone(),
                    state: state.clone(),
                    in_catalog: state.models.iter().any(|c| c.repo == m.repo),
                }
            }
            if not_downloaded_rows.is_empty() {
                div { class: "empty-row", style: "margin-top: 16px;",
                    "All MLX chat models on HuggingFace are downloaded. Nice — you're set."
                }
            } else {
                div { class: "model-section-label", style: "margin-top: 16px;",
                    "Available on HuggingFace ("
                    {not_downloaded_rows.len().to_string()}
                    " more)"
                }
                for m in not_downloaded_rows.iter() {
                    LmDownloadableRow {
                        entry: m.clone(),
                        state: state.clone(),
                        in_catalog: true,
                    }
                }
            }
        }
    }
}

/// Derive a friendly display name from a HF repo id when we don't have
/// a catalog entry to pull one from. Falls back to the last path
/// segment, capitalised, with `-`/`_` collapsed to spaces.
fn derive_display_from_repo(repo: &str) -> String {
    let last = repo.rsplit('/').next().unwrap_or(repo);
    let cleaned = last.replace(['-', '_'], " ");
    let mut chars = cleaned.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
        None => repo.to_string(),
    }
}

#[component]
fn LmDownloadableRow(
    entry: MlxModelEntry,
    state: PublicState,
    /// `true` when this row corresponds to a model in the current HF
    /// catalog fetch; `false` for synthetic entries we synthesise from
    /// `downloaded_models` repos that the catalog doesn't know about
    /// (custom repos, removed repos, etc.). Controls the badge text.
    in_catalog: bool,
) -> Element {
    let repo = entry.repo.clone();
    let display = entry.display.clone();
    let is_active = state.model == repo;
    let is_downloaded = state.downloaded_models.contains(&repo);
    let is_downloading = state.downloading.as_deref() == Some(repo.as_str());
    let is_benchmarking = state.benchmarking.as_deref() == Some(repo.as_str());
    let progress = if is_downloading { state.download_progress } else { 0.0 };
    let pct = (progress * 100.0).round() as i32;

    // Size: actual disk size if downloaded, else catalog-reported
    // expected size, else None ("—").
    let size_text = if is_downloaded {
        state.downloaded_sizes.get(&repo).map(|b| crate::system::format_bytes(*b))
    } else {
        state.catalog_sizes.get(&repo).map(|b| crate::system::format_bytes(*b))
    };
    let speed_text = state.model_speeds.get(&repo).cloned();

    // ── VRAM / fit estimation ────────────────────────────────────────
    // Size on disk is the dominant factor for MLX peak memory (the
    // weights stay quantized, so the file footprint IS the load
    // footprint plus a small KV-cache overhead). Use the actual on-
    // disk size if downloaded, otherwise the HF-reported expected
    // size. If neither is known we skip the fit chip entirely.
    let file_size_bytes: Option<u64> = if is_downloaded {
        state.downloaded_sizes.get(&repo).copied()
    } else {
        state.catalog_sizes.get(&repo).copied()
    };
    let total_memory = state
        .host
        .as_ref()
        .map(|s| s.total_memory_bytes)
        .unwrap_or(0);
    let fit = file_size_bytes
        .map(|bytes| {
            let est = estimate_vram_bytes(bytes, entry.quant.as_deref());
            (est, fit_status(est, total_memory))
        });
    // Tooltip text for the VRAM chip — pre-compute here so we don't
    // need `let` bindings inside the RSX block (Dioxus 0.7 only
    // accepts expressions in attribute position).
    let vram_tip: Option<String> = fit.as_ref().map(|(est, _)| {
        if total_memory > 0 {
            format!(
                "≈ {} estimated peak memory · {}/{} device RAM ({:.0}%)",
                format_bytes(*est),
                format_bytes(*est),
                format_bytes(total_memory),
                (*est as f64 / total_memory as f64) * 100.0
            )
        } else {
            format!("≈ {} estimated peak memory", format_bytes(*est))
        }
    });
    // If the model won't fit, the Download button still works (the
    // user might have a clean machine after a restart, or want to
    // try anyway) but we visually dim it and surface a confirm
    // toast on click.
    let wont_fit = matches!(fit, Some((_, FitStatus::WontFit)));

    let (button_label, button_class): (String, String) = if is_active {
        ("Active".to_string(), "btn-active".to_string())
    } else if is_downloading {
        (format!("{pct}%"), "btn-progress".to_string())
    } else if is_downloaded {
        ("Use".to_string(), "btn-use".to_string())
    } else if wont_fit {
        ("Won't fit".to_string(), "btn-download disabled-fit".to_string())
    } else {
        ("Download".to_string(), "btn-download".to_string())
    };

    let (badge_class, badge_text) = if in_catalog {
        ("badge ok", "mlx-community")
    } else {
        ("badge cached", "cached")
    };

    rsx! {
        div {
            class: if is_active { "model-row active" } else if wont_fit { "model-row wont-fit" } else { "model-row" },
            div { class: "model-info",
                div { class: "model-name",
                    if is_active { span { class: "star", "★" } }
                    if is_downloaded && !is_active { span { class: "check", "✓" } }
                    "{display}"
                    span { class: "{badge_class}", "{badge_text}" }
                }
                div { class: "model-repo", "{repo}" }
                // Size + speed + VRAM-fit metadata row.
                //
                // We render a placeholder "fetching size…" chip for
                // catalog rows whose size hasn't streamed in yet. The
                // background prefetch (`prefetch_repo_sizes`) populates
                // `state.catalog_sizes` over a few seconds after boot;
                // without this placeholder the row would look empty
                // and the user would think the estimate is broken.
                //
                // Render the meta row whenever the catalog has loaded
                // AND we have either real data OR a reason to expect
                // data soon (i.e. this is a catalog row that hasn't
                // been downloaded yet — the prefetch will fill it in).
                // Without the `in_catalog && !is_downloaded` branch
                // the row stays completely empty during the
                // ~10-second prefetch window, which reads as "the
                // VRAM estimator is broken" rather than "fetching".
                if size_text.is_some()
                    || speed_text.is_some()
                    || fit.is_some()
                    || (in_catalog && !is_downloaded)
                {
                    div { class: "model-meta",
                        if let Some(sz) = size_text.as_ref() {
                            span { class: "model-meta-chip size",
                                span { class: "meta-icon", "⛁" }
                                "{sz}"
                            }
                        } else if in_catalog && !is_downloaded {
                            // Catalog row, not yet measured, and not
                            // yet downloaded (no on-disk size to
                            // fall back to). Show a small "fetching"
                            // pill so the user knows the chip will
                            // appear shortly.
                            span { class: "model-meta-chip size loading",
                                span { class: "meta-icon spinner" }
                                "fetching size…"
                            }
                        }
                        if let Some((est, status)) = fit.as_ref() {
                            span {
                                class: "model-meta-chip vram",
                                title: vram_tip.as_deref().unwrap_or(""),
                                span { class: "meta-icon", "🧠" }
                                "≈ {format_bytes(*est)}"
                                span { class: "{status.css_class()}", "{status.label()}" }
                            }
                        }
                        if let Some(sp) = speed_text.as_ref() {
                            span { class: "model-meta-chip speed",
                                span { class: "meta-icon", "⚡" }
                                "{sp}"
                            }
                        }
                    }
                }
                if wont_fit {
                    div { class: "model-warn",
                        "Estimated peak memory exceeds this Mac's unified memory. The model will likely fail to load or push heavily into swap."
                    }
                }
                if is_downloading {
                    div { class: "model-progress",
                        div {
                            class: "model-progress-fill",
                            style: "width: {pct}%;",
                        }
                    }
                    div { class: "model-progress-text",
                        span { "Downloading…" }
                        span { class: "pct", "{pct}%" }
                    }
                }
            }
            div { class: "model-actions",
                button {
                    class: "{button_class}",
                    disabled: (is_downloading && !is_active) || wont_fit,
                    onclick: move |_| {
                        let st = use_context::<AppState>();
                        if is_active {
                            return;
                        }
                        if is_downloading {
                            return;
                        }
                        if is_downloaded {
                            st.send_cmd(UiCommand::UseModel { repo: repo.clone() });
                        } else {
                            st.send_cmd(UiCommand::DownloadModel { repo: repo.clone() });
                        }
                    },
                    "{button_label}"
                }
                if is_downloading {
                    button {
                        class: "btn-cancel",
                        title: "Cancel download",
                        onclick: {
                            let repo = repo.clone();
                            move |_| {
                                let st = use_context::<AppState>();
                                st.send_cmd(UiCommand::CancelDownload { repo: repo.clone() });
                            }
                        },
                        "✕"
                    }
                } else if is_downloaded && !is_active {
                    // Speed-test button — only shown when the row has
                    // an actual model on disk. While the benchmark is
                    // running, the button collapses into a spinner.
                    if is_benchmarking {
                        span { class: "speed-testing",
                            span { class: "spinner" }
                            "Testing…"
                        }
                    } else {
                        button {
                            class: "btn-speed",
                            title: "Measure tokens/sec on this Mac",
                            onclick: {
                                let repo = repo.clone();
                                move |_| {
                                    let st = use_context::<AppState>();
                                    st.send_cmd(UiCommand::BenchmarkModel { repo: repo.clone() });
                                }
                            },
                            if speed_text.is_some() { "↻ Re-test" } else { "▶ Test" }
                        }
                    }
                    button {
                        class: "btn-delete",
                        title: "Delete from cache",
                        onclick: {
                            let repo = repo.clone();
                            move |_| {
                                let st = use_context::<AppState>();
                                st.send_cmd(UiCommand::DeleteModel { repo: repo.clone() });
                            }
                        },
                        "✕"
                    }
                }
            }
        }
    }
}

// ─── MLX-Whisper tab ───────────────────────────────────────────────────────

#[component]
fn WhisperTab(
    state: PublicState,
    custom_repo: Signal<String>,
    refreshing: Signal<bool>,
) -> Element {
    let mlx_w_ok = state.backends.mlx_whisper_available;
    let total = state.wmodels.len();
    let downloaded_count = state.downloaded_wmodels.len();

    rsx! {
        div {
            DeviceCard { state: state.clone() }
            div { class: "status-strip",
                span { class: "status-pill-inline",
                    if mlx_w_ok { "mlx-whisper: ✓" } else { "mlx-whisper: ✗ (pip install mlx-whisper)" }
                }
                span { class: "status-pill-inline",
                    if state.wmodels_loaded {
                        "HuggingFace: mlx-community ✓"
                    } else if total > 0 {
                        "Loading from HuggingFace…"
                    } else {
                        "HuggingFace: not loaded"
                    }
                }
                span { class: "status-pill-inline", "{downloaded_count} downloaded" }
            }
            div { class: "drawer-section",
                div { class: "drawer-head",
                    div { class: "drawer-label", "MLX-Whisper (STT) — HuggingFace (mlx-community)" }
                    button {
                        class: "btn-cleanup",
                        disabled: refreshing(),
                        onclick: move |_| {
                            let mut r = refreshing;
                            spawn(async move {
                                r.set(true);
                                match mlx_models::fetch_whisper_models(true).await {
                                    Ok(models) if !models.is_empty() => {
                                        let st = use_context::<AppState>();
                                        let entries: Vec<MlxModelEntry> = models
                                            .iter()
                                            .map(|m| MlxModelEntry {
                                                repo: m.repo.clone(),
                                                display: m.display.clone(),
                                                // Whisper repos don't carry
                                                // a quantization hint;
                                                // estimator uses default.
                                                quant: None,
                                            })
                                            .collect();
                                        let count = entries.len();
                                        {
                                            let mut g = st.inner.lock();
                                            g.pub_state.wmodels = entries;
                                            g.pub_state.wmodels_loaded = true;
                                            drop(g);
                                            st.emit(AppEvent::Ok {
                                                msg: format!(
                                                    "Refreshed {count} MLX-Whisper models from HuggingFace"
                                                ),
                                            });
                                            st.emit(AppEvent::State(Box::new(st.snapshot())));
                                        }
                                    }
                                    Ok(_) => {
                                        let st = use_context::<AppState>();
                                        st.emit(AppEvent::Error {
                                            msg: "HuggingFace returned no Whisper models".into(),
                                        });
                                    }
                                    Err(e) => {
                                        let st = use_context::<AppState>();
                                        st.emit(AppEvent::Error {
                                            msg: format!("Refresh failed: {e}"),
                                        });
                                    }
                                }
                                r.set(false);
                            });
                        },
                        if refreshing() { "Refreshing…" } else { "Refresh from HF" }
                    }
                }
                if !mlx_w_ok {
                    div { class: "empty-row", "Install mlx-whisper into the project .venv: source .venv/bin/activate && pip install mlx-whisper" }
                } else if total == 0 {
                    div { class: "empty-row", "Loading models…" }
                } else {
                    WhisperModelList { state: state.clone() }
                }
                div { class: "empty-row", style: "margin-top: 12px; font-size: 12px; opacity: 0.7;",
                    "MLX-Whisper models range from ~75 MB (tiny) to ~3 GB (large-v3). Whisper.cpp backend has been removed."
                }
            }
            div { class: "drawer-section",
                div { class: "drawer-label", "Custom HuggingFace Whisper repo" }
                div { class: "field",
                    input {
                        class: "drawer-input",
                        placeholder: "mlx-community/whisper-large-v3-turbo",
                        value: "{custom_repo}",
                        oninput: move |evt| custom_repo.set(evt.value()),
                    }
                }
                div { class: "drawer-hint",
                    "Paste any mlx-community whisper-* repo id (e.g. distil variants)."
                }
                button {
                    class: "btn-use",
                    style: "margin-top: 8px;",
                    disabled: custom_repo().trim().is_empty(),
                    onclick: move |_| {
                        let repo = custom_repo().trim().to_string();
                        if repo.is_empty() {
                            return;
                        }
                        let st = use_context::<AppState>();
                        st.send_cmd(UiCommand::DownloadWhisperModel { repo: repo.clone() });
                        st.send_cmd(UiCommand::UseWhisperModel { repo });
                    },
                    "Download & use"
                }
            }
        }
    }
}

#[component]
fn WhisperModelList(state: PublicState) -> Element {
    // Catalog ∩ downloaded — entries we know both the friendly name
    // AND the "downloaded" state for.
    let mut downloaded_rows: Vec<MlxModelEntry> = state
        .wmodels
        .iter()
        .filter(|m| state.downloaded_wmodels.contains(&m.repo))
        .cloned()
        .collect();

    // Downloaded repos that the current catalog doesn't know about
    // (custom repos, removed repos). Synthesise a row so the user can
    // still see + Use + Delete them.
    for repo in state.downloaded_wmodels.iter() {
        if !state.wmodels.iter().any(|m| &m.repo == repo) {
            downloaded_rows.push(MlxModelEntry {
                repo: repo.clone(),
                display: derive_display_from_repo(repo),
                quant: None,
            });
        }
    }

    let mut not_downloaded_rows: Vec<_> = state
        .wmodels
        .iter()
        .filter(|m| !state.downloaded_wmodels.contains(&m.repo))
        .cloned()
        .collect();

    downloaded_rows.sort_by(|a, b| a.display.cmp(&b.display));
    not_downloaded_rows.sort_by(|a, b| a.display.cmp(&b.display));

    rsx! {
        div { class: "model-list",
            div { class: "model-section-label",
                "✓ Downloaded ("
                {downloaded_rows.len().to_string()}
                ")"
            }
            for m in downloaded_rows.iter() {
                WhisperDownloadableRow {
                    entry: m.clone(),
                    state: state.clone(),
                    in_catalog: state.wmodels.iter().any(|c| c.repo == m.repo),
                }
            }
            if not_downloaded_rows.is_empty() {
                div { class: "empty-row", style: "margin-top: 16px;",
                    "All MLX-Whisper models on HuggingFace are downloaded."
                }
            } else {
                div { class: "model-section-label", style: "margin-top: 16px;",
                    "Available on HuggingFace ("
                    {not_downloaded_rows.len().to_string()}
                    " more)"
                }
                for m in not_downloaded_rows.iter() {
                    WhisperDownloadableRow {
                        entry: m.clone(),
                        state: state.clone(),
                        in_catalog: true,
                    }
                }
            }
        }
    }
}

#[component]
fn WhisperDownloadableRow(
    entry: MlxModelEntry,
    state: PublicState,
    /// `true` for catalog rows; `false` for synthetic "cached only"
    /// entries we synthesise from `downloaded_wmodels` repos that the
    /// catalog doesn't know about. Controls the badge text.
    in_catalog: bool,
) -> Element {
    let repo = entry.repo.clone();
    let display = entry.display.clone();
    let is_active = state.wmodel == repo;
    let is_downloaded = state.downloaded_wmodels.contains(&repo);
    let is_downloading = state.downloading_wmodel.as_deref() == Some(repo.as_str());
    let is_benchmarking = state.wmodel_benchmarking.as_deref() == Some(repo.as_str());
    let progress = if is_downloading { state.wmodel_download_progress } else { 0.0 };
    let pct = (progress * 100.0).round() as i32;

    let size_text = if is_downloaded {
        state.downloaded_sizes.get(&repo).map(|b| crate::system::format_bytes(*b))
    } else {
        state.catalog_sizes.get(&repo).map(|b| crate::system::format_bytes(*b))
    };
    let speed_text = state.wmodel_speeds.get(&repo).cloned();

    // ── VRAM / fit estimation (Whisper) ──────────────────────────────
    // MLX-Whisper models are tiny compared to chat LLMs (≤ 1.5 GB)
    // so the "WontFit" branch is mostly a safety net for very small
    // Macs (8 GB). The user still gets a "Fits" badge so they know
    // exactly how much headroom they have.
    let file_size_bytes: Option<u64> = if is_downloaded {
        state.downloaded_sizes.get(&repo).copied()
    } else {
        state.catalog_sizes.get(&repo).copied()
    };
    let total_memory = state
        .host
        .as_ref()
        .map(|s| s.total_memory_bytes)
        .unwrap_or(0);
    let fit = file_size_bytes
        .map(|bytes| {
            let est = estimate_vram_bytes(bytes, entry.quant.as_deref());
            (est, fit_status(est, total_memory))
        });
    // Pre-compute tooltip text outside the RSX block (Dioxus 0.7
    // doesn't allow `let` bindings in attribute position).
    let vram_tip: Option<String> = fit.as_ref().map(|(est, _)| {
        if total_memory > 0 {
            format!(
                "≈ {} estimated peak memory · {}/{} device RAM ({:.0}%)",
                format_bytes(*est),
                format_bytes(*est),
                format_bytes(total_memory),
                (*est as f64 / total_memory as f64) * 100.0
            )
        } else {
            format!("≈ {} estimated peak memory", format_bytes(*est))
        }
    });
    let wont_fit = matches!(fit, Some((_, FitStatus::WontFit)));

    let (button_label, button_class): (String, String) = if is_active {
        ("Active".to_string(), "btn-active".to_string())
    } else if is_downloading {
        (format!("{pct}%"), "btn-progress".to_string())
    } else if is_downloaded {
        ("Use".to_string(), "btn-use".to_string())
    } else if wont_fit {
        ("Won't fit".to_string(), "btn-download disabled-fit".to_string())
    } else {
        ("Download".to_string(), "btn-download".to_string())
    };

    let (badge_class, badge_text) = if in_catalog {
        ("badge ok", "mlx-community")
    } else {
        ("badge cached", "cached")
    };

    rsx! {
        div {
            class: if is_active { "model-row active" } else if wont_fit { "model-row wont-fit" } else { "model-row" },
            div { class: "model-info",
                div { class: "model-name",
                    if is_active { span { class: "star", "★" } }
                    if is_downloaded && !is_active { span { class: "check", "✓" } }
                    "{display}"
                    span { class: "{badge_class}", "{badge_text}" }
                }
                div { class: "model-repo", "{repo}" }
                // Same fix as the LmDownloadableRow above — the meta
                // row needs to render during the prefetch window so
                // the "fetching size…" pill is visible.
                if size_text.is_some()
                    || speed_text.is_some()
                    || fit.is_some()
                    || (in_catalog && !is_downloaded)
                {
                    div { class: "model-meta",
                        if let Some(sz) = size_text.as_ref() {
                            span { class: "model-meta-chip size",
                                span { class: "meta-icon", "⛁" }
                                "{sz}"
                            }
                        } else if in_catalog && !is_downloaded {
                            span { class: "model-meta-chip size loading",
                                span { class: "meta-icon spinner" }
                                "fetching size…"
                            }
                        }
                        if let Some((est, status)) = fit.as_ref() {
                            span {
                                class: "model-meta-chip vram",
                                title: vram_tip.as_deref().unwrap_or(""),
                                span { class: "meta-icon", "🧠" }
                                "≈ {format_bytes(*est)}"
                                span { class: "{status.css_class()}", "{status.label()}" }
                            }
                        }
                        if let Some(sp) = speed_text.as_ref() {
                            span { class: "model-meta-chip speed",
                                span { class: "meta-icon", "⚡" }
                                "{sp}"
                            }
                        }
                    }
                }
                if wont_fit {
                    div { class: "model-warn",
                        "Estimated peak memory exceeds this Mac's unified memory. The model will likely fail to load or push heavily into swap."
                    }
                }
                if is_downloading {
                    div { class: "model-progress",
                        div {
                            class: "model-progress-fill",
                            style: "width: {pct}%;",
                        }
                    }
                    div { class: "model-progress-text",
                        span { "Downloading…" }
                        span { class: "pct", "{pct}%" }
                    }
                }
            }
            div { class: "model-actions",
                button {
                    class: "{button_class}",
                    disabled: (is_downloading && !is_active) || wont_fit,
                    onclick: move |_| {
                        let st = use_context::<AppState>();
                        if is_active {
                            return;
                        }
                        if is_downloading {
                            return;
                        }
                        if is_downloaded {
                            st.send_cmd(UiCommand::UseWhisperModel { repo: repo.clone() });
                        } else {
                            st.send_cmd(UiCommand::DownloadWhisperModel { repo: repo.clone() });
                        }
                    },
                    "{button_label}"
                }
                if is_downloading {
                    button {
                        class: "btn-cancel",
                        title: "Cancel download",
                        onclick: {
                            let repo = repo.clone();
                            move |_| {
                                let st = use_context::<AppState>();
                                st.send_cmd(UiCommand::CancelWhisperDownload { repo: repo.clone() });
                            }
                        },
                        "✕"
                    }
                } else if is_downloaded && !is_active {
                    if is_benchmarking {
                        span { class: "speed-testing",
                            span { class: "spinner" }
                            "Testing…"
                        }
                    } else {
                        button {
                            class: "btn-speed",
                            title: "Measure transcription latency",
                            onclick: {
                                let repo = repo.clone();
                                move |_| {
                                    let st = use_context::<AppState>();
                                    st.send_cmd(UiCommand::BenchmarkWhisperModel { repo: repo.clone() });
                                }
                            },
                            if speed_text.is_some() { "↻ Re-test" } else { "▶ Test" }
                        }
                    }
                    button {
                        class: "btn-delete",
                        title: "Delete from cache",
                        onclick: {
                            let repo = repo.clone();
                            move |_| {
                                let st = use_context::<AppState>();
                                st.send_cmd(UiCommand::DeleteWhisperModel { repo: repo.clone() });
                            }
                        },
                        "✕"
                    }
                }
            }
        }
    }
}