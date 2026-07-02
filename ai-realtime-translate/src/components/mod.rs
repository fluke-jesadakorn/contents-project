//! Top-level UI components — converted from the embedded HTML/CSS in
//! `realtime_translator.py`.

pub mod drawer;
pub mod feed;
pub mod footer;
pub mod models_modal;
pub mod status_pill;
pub mod toolbar;
pub mod waveform;

/// Embed the global stylesheet (CSS from the original HTML).
pub const ROOT_STYLE: &str = include_str!("styles.css");