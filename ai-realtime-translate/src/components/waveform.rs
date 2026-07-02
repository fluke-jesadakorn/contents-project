//! Waveform — rolling level meter bars.

use dioxus::prelude::*;

#[component]
pub fn Waveform(level: f32, bars: Vec<f32>) -> Element {
    let active = if level > 0.02 { "waveform active" } else { "waveform" };
    rsx! {
        div { class: "{active}",
            for h in bars.iter() {
                div {
                    class: "wave-bar",
                    style: "height: {h * 100.0:.0}%;",
                }
            }
        }
    }
}