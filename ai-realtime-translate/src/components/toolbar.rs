//! Toolbar — audio input / audio output / src lang / tgt lang / model / record button.

use crate::state::PublicState;
use dioxus::prelude::*;

#[component]
pub fn Toolbar(state: PublicState, on_change: EventHandler<serde_json::Value>) -> Element {
    rsx! {
        div { class: "toolbar",
            Field {
                label: "Audio Input".to_string(),
                icon: Some("🎧".to_string()),
                FieldSelect {
                    value: state.device.clone(),
                    // Map the raw cpal/SCK device name to a friendlier
                    // display label. The `value` (state.device) stays
                    // the raw name so the pipeline can match on it;
                    // only the visible `<option>` text is rewritten.
                    // Rationale: "System Audio (ScreenCaptureKit)" reads
                    // like a developer string. New users on macOS don't
                    // know what SCK is, and they reach for the device
                    // that *sounds* like a speaker — which on a Steam
                    // Link host is the "Steam Streaming Speakers"
                    // virtual OUTPUT (no loopback). The star + "Mac
                    // Speaker Audio" label anchors what the option
                    // actually does: grab whatever's playing on the
                    // Mac's speakers, with zero setup.
                    options: state
                        .devices
                        .iter()
                        .map(|d| (d.name.clone(), display_label_for(&d.name)))
                        .collect(),
                    on_change: move |v: String| on_change.call(serde_json::json!({"device": v})),
                    disabled_hint: None,
                }
            }
            // Inline helper text under the Audio Input dropdown. Shown
            // only when the user has picked a non-SCK source — these
            // are mostly cpal input devices (mic, virtual loopback),
            // and a new user often picks one thinking it's the
            // "speaker" output (e.g. "Steam Streaming Speakers" on a
            // Steam Link host). One short sentence nudges them back
            // to SCK.
            if !state.device.is_empty() && state.device != crate::audio::SYSTEM_AUDIO_DEVICE {
                div { class: "input-hint",
                    "Tip: pick \"★ Mac Speaker Audio\" to capture YouTube / Spotify / any system audio without BlackHole."
                }
            }
            Field {
                label: "Output".to_string(),
                icon: Some("🔊".to_string()),
                // Selects which macOS output device to route all
                // system audio through while recording. Empty
                // string = leave the system default output alone.
                // Pipeline switches before opening SCK and restores
                // on Stop (see `Pipeline::run` in `audio/pipeline.rs`).
                FieldSelect {
                    value: state.output_device.clone(),
                    options: build_output_options(&state),
                    on_change: move |v: String| on_change.call(serde_json::json!({"output_device": v})),
                    disabled_hint: None,
                }
            }
            Field {
                label: "From".to_string(),
                icon: Some("🗣".to_string()),
                FieldSelect {
                    value: state.src_lang.clone(),
                    options: lang_options(),
                    on_change: move |v: String| on_change.call(serde_json::json!({"src_lang": v})),
                    disabled_hint: None,
                }
            }
            SwapButton {}
            Field {
                label: "To".to_string(),
                icon: Some("🌐".to_string()),
                FieldSelect {
                    value: state.tgt_lang.clone(),
                    options: lang_options(),
                    on_change: move |v: String| on_change.call(serde_json::json!({"tgt_lang": v})),
                    disabled_hint: None,
                }
            }
            div { class: "toolbar-sep" }
            FieldNarrow {
                label: "STT".to_string(),
                icon: Some("🎙".to_string()),
                // The toolbar STT dropdown ONLY shows models that are
                // already downloaded to the local HF cache. The full
                // catalog (with Download buttons) lives in the Models
                // modal.
                WhisperDropdown { state: state.clone(), on_change }
            }
            FieldNarrow {
                label: "Model".to_string(),
                icon: Some("⚡".to_string()),
                // The toolbar dropdown ONLY shows models that are
                // already downloaded to the local HF cache. The full
                // catalog (with Download buttons) lives in the Models
                // modal.
                ModelDropdown { state: state.clone(), on_change }
            }
            div { class: "toolbar-spacer" }
            RecordButton {
                listening: state.listening,
                on_toggle: move |_| on_change.call(serde_json::json!({"listening": !state.listening})),
            }
        }
    }
}

#[component]
fn Field(label: String, icon: Option<String>, children: Element) -> Element {
    rsx! {
        div { class: "field",
            div { class: "field-label", "{label}" }
            div { class: "field-control",
                if let Some(ic) = icon {
                    span { class: "field-icon", "{ic}" }
                }
                {children}
            }
        }
    }
}

#[component]
fn FieldNarrow(label: String, icon: Option<String>, children: Element) -> Element {
    rsx! {
        div { class: "field narrow",
            div { class: "field-label", "{label}" }
            div { class: "field-control",
                if let Some(ic) = icon {
                    span { class: "field-icon", "{ic}" }
                }
                {children}
            }
        }
    }
}

#[component]
fn FieldSelect(
    value: String,
    options: Vec<(String, String)>,
    on_change: EventHandler<String>,
    /// Optional non-selectable entry rendered at the top — used by the
    /// model dropdowns to show "⬇ Downloading X…" while a download is
    /// in flight, without polluting the active value. Dioxus 0.7
    /// components don't support default args, so callers must pass
    /// `None` explicitly when no hint is needed.
    disabled_hint: Option<(String, String)>,
) -> Element {
    rsx! {
        select {
            value: "{value}",
            onchange: move |evt| on_change.call(evt.value()),
            if let Some((val, label)) = disabled_hint.as_ref() {
                option {
                    value: "{val}",
                    disabled: true,
                    class: "option-hint",
                    "{label}"
                }
            }
            for (val, label) in options.iter() {
                option { value: "{val}", "{label}" }
            }
        }
    }
}

#[component]
fn SwapButton() -> Element {
    rsx! {
        button { class: "swap-btn", title: "Swap languages",
            svg { view_box: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: "2",
                path { d: "M7 16 L17 8 M17 8 H10 M17 8 V15" }
                path { d: "M17 8 L7 16 M7 16 H14 M7 16 V9" }
            }
        }
    }
}

#[component]
fn RecordButton(listening: bool, on_toggle: EventHandler<()>) -> Element {
    let class = if listening { "rec-btn live" } else { "rec-btn" };
    rsx! {
        button {
            class: "{class}",
            onclick: move |_| on_toggle.call(()),
            span { class: "d" }
            span { class: "stop-ic" }
            if listening { "Stop" } else { "Record" }
        }
    }
}

fn lang_options() -> Vec<(String, String)> {
    vec![
        ("auto".into(), "Auto detect".into()),
        ("en".into(), "English".into()),
        ("de".into(), "German".into()),
        ("fr".into(), "French".into()),
        ("es".into(), "Spanish".into()),
        ("it".into(), "Italian".into()),
        ("ja".into(), "Japanese".into()),
        ("zh".into(), "Chinese".into()),
        ("ko".into(), "Korean".into()),
        ("th".into(), "Thai".into()),
        ("vi".into(), "Vietnamese".into()),
        ("id".into(), "Indonesian".into()),
        ("ru".into(), "Russian".into()),
        ("pt".into(), "Portuguese".into()),
        ("ar".into(), "Arabic".into()),
        ("hi".into(), "Hindi".into()),
        ("tr".into(), "Turkish".into()),
        ("nl".into(), "Dutch".into()),
        ("pl".into(), "Polish".into()),
    ]
}

/// Model dropdown — strictly shows downloaded models. While a download is
/// in flight, renders a disabled "⬇ Downloading X…" hint at the top of
/// the list so the user can see what's in progress without leaving the
/// toolbar. When nothing is downloaded AND nothing is downloading,
/// falls back to a clickable pill that opens the Models modal.
#[component]
fn ModelDropdown(state: PublicState, on_change: EventHandler<serde_json::Value>) -> Element {
    // Catalog ∩ downloaded — entries we know both the friendly name
    // AND the "downloaded" state for.
    let mut downloaded: Vec<(String, String)> = state
        .downloaded_models
        .iter()
        .filter_map(|repo| {
            state
                .models
                .iter()
                .find(|m| &m.repo == repo)
                .map(|m| (m.repo.clone(), m.display.clone()))
        })
        .collect();

    // Synthetic entries for downloaded repos that aren't in the current
    // catalog — custom HF repos typed into the modal's input field, or
    // repos that have been removed from mlx-community since they were
    // downloaded. Without this, downloading such a repo would leave the
    // toolbar showing "No model — open Models" even though the user has
    // a model on disk and active.
    for repo in state.downloaded_models.iter() {
        if !downloaded.iter().any(|(r, _)| r == repo) {
            downloaded.push((repo.clone(), derive_short_display(repo)));
        }
    }

    // ... rest unchanged

    // Build a disabled "downloading" hint for any chat download that's
    // still in flight (i.e. not yet in `downloaded_models`). The repo
    // id is wrapped in a sentinel prefix so the option's value can never
    // collide with a real model repo and accidentally fire as a
    // selection.
    let downloading_hint: Option<(String, String)> = state
        .downloading
        .as_ref()
        .filter(|repo| !state.downloaded_models.contains(repo))
        .map(|repo| {
            let display = state
                .models
                .iter()
                .find(|m| &m.repo == repo)
                .map(|m| m.display.clone())
                .unwrap_or_else(|| {
                    // Custom repo typed into the input — derive a
                    // display name from the last path segment.
                    repo.rsplit('/').next().unwrap_or(repo).to_string()
                });
            (
                format!("__downloading__:{repo}"),
                format!("⬇ Downloading {display}…"),
            )
        });

    // The select's current value: only honor `state.model` if it's
    // actually downloaded. Otherwise leave it blank so the disabled
    // hint (if any) shows as the visible placeholder without making
    // the user think a non-downloaded model is selectable.
    let value = if state.downloaded_models.contains(&state.model) {
        state.model.clone()
    } else {
        String::new()
    };

    let nothing_to_show = downloaded.is_empty() && downloading_hint.is_none();

    rsx! {
        if nothing_to_show {
            button {
                class: "model-pill-empty",
                onclick: move |_| {
                    // Sentinel value — components/root.rs translates
                    // `open_models: true` into `show_models.set(true)`.
                    on_change.call(serde_json::json!({"open_models": true}));
                },
                "No model — open Models"
            }
        } else {
            FieldSelect {
                value,
                options: downloaded,
                on_change: move |v: String| on_change.call(serde_json::json!({"model": v})),
                disabled_hint: downloading_hint,
            }
        }
    }
}

/// STT dropdown — same UX as `ModelDropdown` but for MLX-Whisper.
#[component]
fn WhisperDropdown(state: PublicState, on_change: EventHandler<serde_json::Value>) -> Element {
    // Catalog ∩ downloaded (Whisper-shaped only).
    let mut downloaded: Vec<(String, String)> = state
        .downloaded_wmodels
        .iter()
        .filter_map(|repo| {
            state
                .wmodels
                .iter()
                .find(|m| &m.repo == repo)
                .map(|m| (m.repo.clone(), m.display.clone()))
        })
        .collect();

    // Synthetic entries for downloaded Whisper repos that aren't in the
    // current catalog (custom repo, removed repo). Same rationale as in
    // `ModelDropdown` above.
    for repo in state.downloaded_wmodels.iter() {
        if !downloaded.iter().any(|(r, _)| r == repo) {
            downloaded.push((repo.clone(), derive_short_display(repo)));
        }
    }

    let downloading_hint: Option<(String, String)> = state
        .downloading_wmodel
        .as_ref()
        .filter(|repo| !state.downloaded_wmodels.contains(repo))
        .map(|repo| {
            let display = state
                .wmodels
                .iter()
                .find(|m| &m.repo == repo)
                .map(|m| m.display.clone())
                .unwrap_or_else(|| {
                    repo.rsplit('/').next().unwrap_or(repo).to_string()
                });
            (
                format!("__downloading__:{repo}"),
                format!("⬇ Downloading {display}…"),
            )
        });

    let value = if state.downloaded_wmodels.contains(&state.wmodel) {
        state.wmodel.clone()
    } else {
        String::new()
    };

    let nothing_to_show = downloaded.is_empty() && downloading_hint.is_none();

    rsx! {
        if nothing_to_show {
            button {
                class: "model-pill-empty",
                onclick: move |_| {
                    on_change.call(serde_json::json!({"open_models": true}));
                },
                "No STT — open Models"
            }
        } else {
            FieldSelect {
                value,
                options: downloaded,
                on_change: move |v: String| on_change.call(serde_json::json!({"wmodel": v})),
                disabled_hint: downloading_hint,
            }
        }
    }
}

/// Derive a friendly display name for a HF repo id when we don't have
/// a catalog entry. Used for synthetic "cached only" rows that aren't
/// in the current HF catalog fetch — the user can still see and select
/// their model even if it's been removed from mlx-community or was a
/// custom repo they typed into the Models modal.
///
/// `mlx-community/whisper-large-v3-turbo` → `Whisper Large V3 Turbo`
fn derive_short_display(repo: &str) -> String {
    let last = repo.rsplit('/').next().unwrap_or(repo);
    let cleaned = last.replace(['-', '_'], " ");
    cleaned
        .split_whitespace()
        .map(capitalize_word)
        .collect::<Vec<_>>()
        .join(" ")
}

/// Capitalize the first character of `word`. `whisper` → `Whisper`,
/// `v3` → `V3`, `large` → `Large`. Leaves the rest of the chars
/// untouched (no `to_lowercase()` on the tail — preserves digits and
/// mixed-case model names like `myModel2`).
fn capitalize_word(word: &str) -> String {
    let mut chars = word.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// User-facing display label for a raw device name. Today only the
/// SCK pseudo-device gets a custom label; cpal devices fall through
/// to their raw name (which is what the OS already shows in
/// Audio MIDI Setup, so users can match them up).
fn display_label_for(name: &str) -> String {
    if name == crate::audio::SYSTEM_AUDIO_DEVICE {
        crate::audio::SYSTEM_AUDIO_DISPLAY.to_string()
    } else {
        name.to_string()
    }
}

/// Build the Output dropdown's option list. The first entry is the
/// "(leave system default)" pseudo-option so users can opt out of
/// Foundry touching the system routing entirely.
fn build_output_options(state: &PublicState) -> Vec<(String, String)> {
    let mut opts: Vec<(String, String)> = Vec::with_capacity(state.output_devices.len() + 1);
    opts.push((String::new(), "(system default)".to_string()));
    for d in &state.output_devices {
        opts.push((d.name.clone(), d.name.clone()));
    }
    opts
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_short_display_capitalises_and_joins() {
        assert_eq!(
            derive_short_display("mlx-community/whisper-large-v3-turbo"),
            "Whisper Large V3 Turbo"
        );
        assert_eq!(
            derive_short_display("org/My-Custom_Model"),
            "My Custom Model"
        );
        assert_eq!(derive_short_display("solo"), "Solo");
        assert_eq!(derive_short_display(""), "");
    }
}