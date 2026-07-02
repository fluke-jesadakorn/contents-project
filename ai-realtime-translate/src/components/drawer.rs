//! Drawer — Tune Translation settings panel.

use crate::state::PublicState;
use dioxus::prelude::*;

#[component]
pub fn Drawer(
    state: PublicState,
    on_close: EventHandler<()>,
    on_save: EventHandler<serde_json::Value>,
) -> Element {
    let mut glossary = use_signal(|| state.glossary.clone());
    let mut custom_prompt = use_signal(|| state.custom_prompt.clone());
    let mut concise = use_signal(|| state.concise_translation);
    let mut silence_threshold = use_signal(|| state.vad_silence_threshold);
    let mut max_speech = use_signal(|| state.vad_max_speech_duration);
    let mut show_preview = use_signal(|| false);

    rsx! {
        div {
            class: "modal-bg",
            style: "display: flex;",
            onclick: move |_| on_close.call(()),
            div {
                class: "drawer",
                onclick: move |e| e.stop_propagation(),
                div { class: "drawer-head",
                    h3 { "Tune Translation",
                        small { "Glossary · Prompt · VAD · Backend" }
                    }
                    button { class: "modal-close", onclick: move |_| on_close.call(()), "×" }
                }
                div { class: "drawer-body",
                    Section { label: "Glossary", hint: "preferred terms (one per line)" }
                    textarea {
                        class: "drawer-textarea",
                        placeholder: "Schadenfreude → ความยินดีในความทุกข์ของผู้อื่น\n...",
                        value: "{glossary}",
                        oninput: move |evt| glossary.set(evt.value()),
                    }
                    Section { label: "Custom System Prompt", hint: "appended after glossary" }
                    textarea {
                        class: "drawer-textarea",
                        placeholder: "Always address the listener as 'คุณ'...",
                        value: "{custom_prompt}",
                        oninput: move |evt| custom_prompt.set(evt.value()),
                    }
                    Section { label: "VAD" }
                    RangeRow {
                        label: "Silence threshold (s)",
                        value: silence_threshold() as f64,
                        min: 0.2, max: 3.0, step: 0.1,
                        on_change: move |v: f64| silence_threshold.set(v as f32),
                    }
                    RangeRow {
                        label: "Max speech (s)",
                        value: max_speech() as f64,
                        min: 1.0, max: 15.0, step: 0.5,
                        on_change: move |v: f64| max_speech.set(v as f32),
                    }
                    Section { label: "Output style" }
                    Checkbox {
                        label: "Concise translation",
                        hint: "Use the shortest natural translation — no extra explanation.",
                        checked: concise(),
                        on_change: move |v: bool| concise.set(v),
                    }
                    if show_preview() {
                        Section { label: "Translation Prompt Preview" }
                        div { class: "prompt-preview",
                            "{crate::llm::prompts::build_translation_prompt(&state.src_lang, &state.tgt_lang, &glossary(), &custom_prompt(), concise())}"
                        }
                    }
                }
                div { class: "drawer-actions",
                    button {
                        class: "btn-preview",
                        onclick: move |_| show_preview.set(!show_preview()),
                        if show_preview() { "Hide prompt" } else { "Preview" }
                    }
                    button {
                        class: "btn-save",
                        onclick: move |_| {
                            on_save.call(serde_json::json!({
                                "glossary": glossary(),
                                "custom_prompt": custom_prompt(),
                                "concise_translation": concise(),
                                "vad_silence_threshold": silence_threshold(),
                                "vad_max_speech_duration": max_speech(),
                            }));
                        },
                        "Save & Close"
                    }
                }
            }
        }
    }
}

#[component]
fn Section(label: String, hint: Option<String>) -> Element {
    rsx! {
        div { class: "drawer-section",
            div { class: "drawer-label",
                "{label}"
                if let Some(h) = hint {
                    span { class: "hint", "{h}" }
                }
            }
        }
    }
}

#[component]
fn RangeRow(
    label: String,
    value: f64,
    min: f64,
    max: f64,
    step: f64,
    on_change: EventHandler<f64>,
) -> Element {
    rsx! {
        div { class: "drawer-section",
            div { class: "drawer-label",
                "{label}"
                span { class: "hint", "{value:.1}" }
            }
            input {
                r#type: "range",
                min: "{min}",
                max: "{max}",
                step: "{step}",
                value: "{value}",
                style: "width: 100%; accent-color: var(--red);",
                oninput: move |evt| {
                    if let Ok(v) = evt.value().parse::<f64>() {
                        on_change.call(v);
                    }
                },
            }
        }
    }
}

#[component]
fn Checkbox(
    label: String,
    hint: Option<String>,
    checked: bool,
    on_change: EventHandler<bool>,
) -> Element {
    rsx! {
        label { class: "drawer-checkbox-label",
            input {
                r#type: "checkbox",
                checked: "{checked}",
                onchange: move |evt| on_change.call(evt.checked()),
            }
            div {
                strong { "{label}" }
                if let Some(h) = hint {
                    span { class: "hint", "{h}" }
                }
            }
        }
    }
}