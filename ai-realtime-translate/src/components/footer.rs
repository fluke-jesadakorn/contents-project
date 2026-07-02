//! Footer — backend chips + meta info.

use crate::state::PublicState;
use dioxus::prelude::*;

#[component]
pub fn Footer(state: PublicState) -> Element {
    rsx! {
        footer {
            div { class: "backend-row",
                Chip { label: "MLX-W", on: state.backends.mlx_whisper_available }
                Chip { label: "MLX-LM", on: state.backends.mlx_lm_available }
                Chip { label: "System Audio", on: state.backends.system_audio_available }
            }
            div { class: "footer-meta",
                span { b { "Foundry" } " v0.1.0" }
                span { class: "sep", "·" }
                span { "Apple Silicon · Dioxus" }
            }
        }
    }
}

#[component]
fn Chip(label: String, on: bool) -> Element {
    let class = if on { "backend-chip on" } else { "backend-chip" };
    rsx! {
        div { class: "{class}",
            div { class: "d" }
            "{label}"
        }
    }
}