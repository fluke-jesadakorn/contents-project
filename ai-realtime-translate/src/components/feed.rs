//! Two-pane feed — source transcript on the left, translation on the right.

use crate::state::PublicState;
use dioxus::prelude::*;

#[component]
pub fn Feed(state: PublicState, on_change: EventHandler<serde_json::Value>) -> Element {
    rsx! {
        div { class: "pane",
            PaneHead {
                label: "Source",
                lang: state.src_lang.clone(),
            }
            div { class: "feed",
                if state.history.is_empty() {
                    EmptyState { src: true }
                } else {
                    for e in state.history.iter() {
                        Entry {
                            text: e.src.clone(),
                            ts: e.ts,
                            latency: e.latency.stt,
                            pane_kind: "src".to_string(),
                        }
                    }
                }
            }
        }
        div { class: "pane tgt",
            PaneHead {
                label: "Translation",
                lang: state.tgt_lang.clone(),
            }
            div { class: "feed",
                button {
                    class: "pane-btn",
                    onclick: move |_| on_change.call(serde_json::json!({"clear": true})),
                    "Clear"
                }
                if state.history.is_empty() {
                    EmptyState { src: false }
                } else {
                    for e in state.history.iter() {
                        Entry {
                            text: e.tgt.clone(),
                            ts: e.ts,
                            latency: e.latency.llm,
                            pane_kind: "tgt".to_string(),
                        }
                    }
                }
            }
        }
    }
}

#[component]
fn PaneHead(label: String, lang: String) -> Element {
    rsx! {
        div { class: "pane-head",
            div { class: "pane-title",
                div { class: "pane-label", "{label}" }
                div { class: "pane-lang", "{lang.to_uppercase()}" }
            }
            div { class: "pane-actions" }
        }
    }
}

#[component]
fn Entry(text: String, ts: f64, latency: f32, pane_kind: String) -> Element {
    let ts_str = chrono::DateTime::<chrono::Utc>::from_timestamp_millis((ts * 1000.0) as i64)
        .map(|t| t.with_timezone(&chrono::Local).format("%H:%M:%S").to_string())
        .unwrap_or_else(|| "--:--:--".into());
    rsx! {
        div { class: "entry",
            div { class: "entry-meta",
                span { class: "ts", "{ts_str}" }
                span { class: "dot" }
                span { class: "lat", "{latency:.2}s" }
            }
            div { class: "entry-text", "{text}" }
        }
    }
}

#[component]
fn EmptyState(src: bool) -> Element {
    if src {
        rsx! {
            div { class: "empty",
                svg { class: "empty-icon", view_box: "0 0 24 24", fill: "none", stroke: "currentColor",
                    path { d: "M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" }
                    path { d: "M19 10v2a7 7 0 0 1-14 0v-2" }
                    line { x1: "12", y1: "19", x2: "12", y2: "23" }
                }
                div { class: "empty-title", "Awaiting audio" }
                div { class: "empty-sub",
                    "Press "
                    b { "Record" }
                    " to capture from your selected input (System Audio via ScreenCaptureKit is recommended)."
                }
            }
        }
    } else {
        rsx! {
            div { class: "empty",
                svg { class: "empty-icon", view_box: "0 0 24 24", fill: "none", stroke: "currentColor",
                    path { d: "M5 8 L19 8 L19 19 L5 19 Z" }
                    path { d: "M9 8 V5 a3 3 0 0 1 6 0 V8" }
                }
                div { class: "empty-title", "Translations appear here" }
                div { class: "empty-sub", "Live Thai translations will stream into this pane as you speak." }
            }
        }
    }
}