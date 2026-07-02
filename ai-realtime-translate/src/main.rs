//! Foundry — Realtime Voice Intelligence
//!
//! macOS native app built with Dioxus 0.7.
//! Pipeline: BlackHole 2ch → cpal capture → VAD → denoise → STT → LLM → live UI.
//!
//! Run:  cargo run --release

#![cfg_attr(
    all(not(debug_assertions), target_os = "macos"),
    windows_subsystem = "windows"
)]

mod app;
mod audio;
mod components;
mod config;
mod llm;
mod state;
mod stt;
mod system;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();

    log::info!("Foundry starting…");

    app::launch_desktop();
}