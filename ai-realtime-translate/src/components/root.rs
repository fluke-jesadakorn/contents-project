//! Root component — the main app shell.

use crate::state::{AppEvent, AppState, PublicState};
use dioxus::prelude::*;
use std::sync::Arc;
use std::time::Duration;

pub fn Root(cx: Scope) -> Element {
    let state = use_context::<Arc<AppState>>(cx).unwrap();

    // Subscribe to events and expose the latest PublicState.
    let st = state.clone();
    let latest = use_state(cx, || st.snapshot());
    let level = use_state(cx, || 0.0_f32);
    let toast = use_state(cx, || None::<ToastInfo>);
    let show_models = use_state(cx, || false);
    let show_drawer = use_state(cx, || false);

    // Event subscription.
    {
        let st = state.clone();
        let latest = latest.clone();
        let level = level.clone();
        let toast = toast.clone();
        cx.push_future(async move {
            let mut rx = st.events.subscribe();
            loop {
                match rx.recv().await {
                    Ok(ev) => match ev {
                        AppEvent::State(Box::new(s)) => latest.set(s),
                        AppEvent::Level { v } => level.set(v),
                        AppEvent::Info { msg } if !msg.is_empty() => {
                            toast.set(Some(ToastInfo { kind: ToastKind::Info, msg }));
                            let t = toast.clone();
                            tokio::spawn(async move {
                                tokio::time::sleep(Duration::from_secs(4)).await;
                                t.set(None);
                            });
                        }
                        AppEvent::Ok { msg } => {
                            toast.set(Some(ToastInfo { kind: ToastKind::Ok, msg }));
                            let t = toast.clone();
                            tokio::spawn(async move {
                                tokio::time::sleep(Duration::from_secs(4)).await;
                                t.set(None);
                            });
                        }
                        AppEvent::Error { msg } => {
                            toast.set(Some(ToastInfo {
                                kind: ToastKind::Error,
                                msg,
                                action_label: None,
                                action_url: None,
                            }));
                            let t = toast.clone();
                            tokio::spawn(async move {
                                tokio::time::sleep(Duration::from_secs(8)).await;
                                t.set(None);
                            });
                        }
                        AppEvent::ErrorWithAction {
                            msg,
                            action_label,
                            action_url,
                        } => {
                            toast.set(Some(ToastInfo {
                                kind: ToastKind::Error,
                                msg,
                                action_label: Some(action_label),
                                action_url: Some(action_url),
                            }));
                            let t = toast.clone();
                            tokio::spawn(async move {
                                tokio::time::sleep(Duration::from_secs(20)).await;
                                t.set(None);
                            });
                        }
                        _ => {}
                    },
                    Err(_) => break,
                }
            }
        });
    }

    let s = latest.get().clone();
    let lvl = *level.get();

    cx.render(rsx! {
        style { "{ROOT_STYLE}" }
        div { class: "app",
            // Header
            Header {
                state: s.clone(),
                on_models: move |_| show_models.set(true),
                on_drawer: move |_| show_drawer.set(true),
            }
            // Toolbar
            Toolbar {
                state: s.clone(),
                on_change: move |patch: serde_json::Value| {
                    state.apply_control(patch);
                },
            }
            // Two-pane feed
            main {
                Feed {
                    state: s.clone(),
                    on_change: move |patch: serde_json::Value| {
                        state.apply_control(patch);
                    },
                }
            }
            // Stats bar with waveform
            StatsBar {
                level: lvl,
                state: s.clone(),
            }
            // Footer
            Footer { state: s.clone() }
            // Modals / drawers
            if **show_models {
                ModelsModal {
                    state: s.clone(),
                    on_close: move |_| show_models.set(false),
                }
            }
            if **show_drawer {
                Drawer {
                    state: s.clone(),
                    on_close: move |_| show_drawer.set(false),
                    on_save: move |patch: serde_json::Value| {
                        state.apply_control(patch);
                        show_drawer.set(false);
                    },
                }
            }
            if let Some(t) = toast.get().clone() {
                Toast {
                    info: t,
                    on_dismiss: move |_| toast.set(None),
                }
            }
        }
    })
}

#[derive(Clone)]
struct ToastInfo {
    kind: ToastKind,
    msg: String,
    action_label: Option<String>,
    action_url: Option<String>,
}

#[derive(Clone, Copy)]
enum ToastKind {
    Info,
    Ok,
    Error,
}

fn Toast(cx: Scope) -> Element {
    let info = cx.props.info.clone();
    let on_dismiss = cx.props.on_dismiss.clone();
    let class = match info.kind {
        ToastKind::Info => "toast show",
        ToastKind::Ok => "toast show ok",
        ToastKind::Error => "toast show err",
    };
    let action = info.action_label.clone().zip(info.action_url.clone());
    let state_for_retry = use_context::<std::sync::Arc<crate::state::AppState>>(cx)
        .unwrap()
        .clone();
    cx.render(rsx! {
        div { class: "{class}",
            span { class: "toast-msg", "{info.msg}" }
            if let Some((label, url)) = action {
                button {
                    class: "toast-action",
                    onclick: move |_| {
                        // Hand off to the OS shell so macOS routes
                        // `x-apple.systempreferences:` URLs through the
                        // correct handler (System Settings.app on
                        // Ventura+, legacy System Preferences on older
                        // builds). `Command::new("open")` is async-safe
                        // and doesn't block the UI thread.
                        let _ = std::process::Command::new("open")
                            .arg(&url)
                            .spawn();

                        // Dismiss the toast right away — the action is
                        // taken, no need to leave the toast on screen
                        // for the full 20s lifetime.
                        on_dismiss.call(());

                        // Schedule an auto-retry. We give the user 6s
                        // — usually enough to flip the toggle in
                        // System Settings and switch back. The retry
                        // bumps `audio_retry_signal`; the pipeline
                        // watches it and resets its TCC latch without
                        // requiring the user to toggle Listen.
                        let st = state_for_retry.clone();
                        tokio::spawn(async move {
                            tokio::time::sleep(Duration::from_secs(6)).await;
                            let current = st.snapshot().audio_retry_signal;
                            st.apply_control(serde_json::json!({
                                "audio_retry_signal": current + 1,
                            }));
                        });
                    },
                    "{label}"
                }
            }
        }
    })
}

// ─────────────────────────────────────────────────────────────────────────
// Components
// ─────────────────────────────────────────────────────────────────────────

fn Header(cx: Scope) -> Element {
    let s = cx.props.state.clone();
    let on_models = cx.props.on_models.clone();
    let on_drawer = cx.props.on_drawer.clone();

    let header_class = if s.listening { "recording" } else { "" };

    cx.render(rsx! {
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
            StatusPill { state: s.clone() }
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
    })
}

fn StatsBar(cx: Scope) -> Element {
    let lvl = cx.props.level;
    let s = cx.props.state.clone();

    // Build 64 bars whose heights follow the level meter (rolling wave).
    // Bars are flat-zero when there's no audio signal — that prevents a
    // row of 2px-tall rectangles from rendering as a "dashed line" at the
    // bottom of the stats bar during quiet stretches of recording.
    let bars: Vec<f32> = (0..64)
        .map(|i| {
            let phase = (i as f32 / 64.0) * std::f32::consts::PI * 4.0;
            let base = (phase.sin() + 1.0) * 0.5;
            base * lvl
        })
        .collect();

    cx.render(rsx! {
        div { class: "stats-bar",
            Waveform { level: lvl, bars: bars }
            div { class: "stat-pill",
                span { class: "l", "STT" }
                span { class: "v",
                    if s.stt_busy { "🎙 busy" } else { "idle" }
                }
            }
            div { class: "stat-pill",
                span { class: "l", "LLM" }
                span { class: "v",
                    if s.llm_busy { "⚡ busy" } else { "idle" }
                }
            }
            div { class: "stat-pill ok",
                span { class: "l", "Segments" }
                span { class: "v", "{s.history.len()}" }
            }
        }
    })
}

// ─────────────────────────────────────────────────────────────────────────
// Global stylesheet — ported verbatim from `realtime_translator.py` HTML.
// ─────────────────────────────────────────────────────────────────────────

const ROOT_STYLE: &str = include_str!("styles.css");

use super::drawer::Drawer;
use super::feed::Feed;
use super::footer::Footer;
use super::models_modal::ModelsModal;
use super::status_pill::StatusPill;
use super::toolbar::Toolbar;
use super::waveform::Waveform;