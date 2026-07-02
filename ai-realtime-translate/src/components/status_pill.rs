//! Status pill — live/recording indicator + clock.

use crate::state::PublicState;
use dioxus::prelude::*;
use std::time::Duration;

#[component]
pub fn StatusPill(state: PublicState) -> Element {
    let mut now = use_signal(chrono::Local::now);
    use_future(move || async move {
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            now.set(chrono::Local::now());
        }
    });

    let class = if state.listening { "status-pill live" } else { "status-pill" };
    let text = if state.listening { "LIVE" } else { "Ready" };
    let clock = now().format("%H:%M:%S").to_string();

    rsx! {
        div { class: "{class}",
            div { class: "dot" }
            div { class: "status-text", "{text}" }
            div { class: "clock", "{clock}" }
        }
    }
}