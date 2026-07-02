# Foundry Desktop (Dioxus / Rust)

Native macOS app for the Foundry realtime voice translation pipeline.
Built with [Dioxus 0.7](https://dioxuslabs.com) — no web server, no Python at runtime (except as the MLX bridge for STT + translation).

## What changed vs. the legacy Python app

| Layer | Python (legacy) | Rust + Dioxus (this) |
| --- | --- | --- |
| GUI | ~1300 LoC HTML/CSS/JS served at `http://127.0.0.1:8765` | Dioxus RSX + WebKit webview, native `.app` bundle |
| Audio capture — mic / BlackHole | `sounddevice` | `cpal` (CoreAudio) |
| Audio capture — **system audio** | BlackHole + Multi-Output routing | **ScreenCaptureKit** (same engine OBS uses on macOS 13+) |
| VAD | `webrtcvad` | pure-Rust RMS gate (matches Python semantics) |
| Denoise | `noisereduce` (PyO3) | pure-Rust FFT spectral gating (`rustfft`) |
| STT | `whisper-cli` subprocess OR `mlx-whisper` via Python | Same — both via subprocess, MLX uses the project's `.venv` |
| Translation | Ollama HTTP OR MLX-LM | **MLX-LM only** via the project's `.venv` (Apple Silicon ANE) |
| Event bus | SSE over `http.server.ThreadingHTTPServer` | `tokio::sync::broadcast` (in-process) |

## Audio sources

Foundry now supports two capture paths, both wired into the same VAD → denoise → STT → MLX-LM pipeline:

1. **System Audio (ScreenCaptureKit)** — the default. Captures every audio
   source playing on the Mac (excluding the Foundry process itself). No
   BlackHole, no virtual audio driver, no Multi-Output Device setup. Requires
   macOS 13+ and a one-time Screen Recording permission grant (the app
   prompts you the first time you press Record). Same engine OBS uses.
2. **cpal input device** — microphone, BlackHole 2ch, or any other
   CoreAudio input. Use the Audio Input dropdown to pick a device; useful
   when you want a specific source (e.g. a mic only).

## Translation backends

MLX-LM only. The translation model dropdown lists curated mlx-community
repos (gemma3/4, llama3.1/3.2, qwen2.5/3, mistral, aya, phi-3). Models
download automatically on first use from Hugging Face and cache under
`~/.cache/huggingface/`.

Translation memory (last 5 segments) is threaded into the system prompt so
pronouns and tone stay consistent across segments.

## Build

```bash
# From this directory:
cargo build --release          # ~1 min on M-series
dx bundle --package-types macos
open ../dist/Foundry.app
```

The first build needs internet to fetch deps; subsequent rebuilds are incremental.

## Run from terminal

```bash
cargo run --release
```

Foundry will request **microphone** access on first launch (for cpal/BlackHole paths) and
**Screen Recording** access the first time you select System Audio and press Record. Both
TCC prompts are one-time.

## Run with hot reload (dev loop)

```bash
dx serve --hot-reload true
```

This is the recommended dev workflow. `dx serve` watches `src/` and
recompiles incrementally on every save, then reopens the WebKit
webview with the new binary. Build is incremental — first compile
~1 min, subsequent rebuilds ~1–3 s.

While the server is running, the CLI exposes a few shortcuts:

| Key | Action |
| --- | --- |
| `r` | Force a rebuild |
| `p` | Toggle auto-rebuild on file change |
| `v` | Toggle verbose build logging |
| `/` | Show full shortcut list |
| `Ctrl-C` | Stop the server |

**What hot-reloads well:**
- RSX markup (anything in `src/components/*.rs` `rsx! { … }` blocks)
- CSS in `src/components/styles.css` (picked up on next save)
- New `state` fields, `AppEvent` variants, `PublicState` changes —
  the WebKit window refreshes after the incremental Rust rebuild

**What needs a manual restart:**
- `Cargo.toml` / `Cargo.lock` dependency changes (full `cargo build`)
- Changes to `#[cfg(target_os = "macos")]` blocks (the SCK FFI
  bindings, entitlements, plist keys) — `Ctrl-C` and re-`dx serve`
- First run of a session (no binary cached yet)

**Logs.** `dx serve` prints both the Dioxus CLI banner and every
`log::*!` from the Rust code. App-side lines show up prefixed
with `ERROR` even at INFO level — that's a Dioxus CLI logging
quirk, not a real error. To filter, run with `dx serve 2>&1 |
grep -v "ERROR"` and pipe through `rg "INFO|WARN"` etc.

## Tests

```bash
cargo test --release --bins
```

## Architecture

```
┌─────────────────────────── Dioxus 0.7 (WebKit) ───────────────────────────┐
│  RSX UI (components/*.rs)                                                 │
│    Header · Toolbar · Feed · StatsBar · Footer · Drawer · ModelsModal     │
│         ↕ signals / event broadcast                                       │
│  AppState (parking_lot::Mutex + broadcast::Sender)                         │
└───────────────────────────────────────────────────────────────────────────┘
                                        │
         ┌──────────────────────────────┼──────────────────────────────┐
         │                              │                              │
   ┌─────▼─────┐                  ┌──────▼──────┐                ┌──────▼──────┐
   │  audio    │  mono f32 16 kHz │   stt       │  base64/JSON   │   llm       │
   │  pipeline │ ────────────────▶│  transcribe │ ──────────────▶│  translate  │
   │  (one OS  │  via async_chan  │  (mlx_whisper│  transcribed   │  (MLX-LM +  │
   │  thread)  │                  │  or whisper │  text          │  memory +   │
   │           │                  │  -cli)      │                │  retry)     │
   └────▲──────┘                  └─────────────┘                └─────────────┘
        │
        │   ┌─────────────────────────┐    ┌──────────────────────────────┐
        │   │  cpal input device      │    │  ScreenCaptureKit (system)   │
        │   │  (BlackHole, mic, …)    │    │  (macOS 13+, OBS engine)     │
        │   └─────────────────────────┘    └──────────────────────────────┘
        │
   AppState.control.device   ⇒  "System Audio (ScreenCaptureKit)"  or  a cpal device name
```

Each subsystem is on its own thread / runtime:

- **UI** — Dioxus WebKit (main thread)
- **Audio** — dedicated OS thread + small tokio runtime for stream reconciliation; VSM drains both cpal and SCK into a single chunk queue
- **STT** — async task that pulls from the audio chunk channel
- **LLM** — invoked inline by the STT task per segment (with translation memory)

## Files

```
desktop/
├── Cargo.toml                # workspace manifest
├── Dioxus.toml               # bundle config
├── Info.plist                # macOS app metadata + permission strings
├── entitlements.plist        # mic + audio-input + screen-capture entitlements
├── assets/icon.svg           # source icon (PNG/ICNS generated)
└── src/
    ├── main.rs               # entry point
    ├── app.rs                # Dioxus root + UI shell + bootstrap
    ├── config.rs             # constants (sample rate, model paths, etc.)
    ├── components/
    │   ├── mod.rs            # module index
    │   ├── styles.css        # ported from the Python app (verbatim)
    │   ├── status_pill.rs
    │   ├── toolbar.rs
    │   ├── feed.rs
    │   ├── waveform.rs
    │   ├── footer.rs
    │   ├── drawer.rs
    │   └── models_modal.rs
    ├── audio/
    │   ├── capture.rs        # cpal stream → mono f32
    │   ├── system_capture.rs # ScreenCaptureKit → mono f32 (macOS 13+)
    │   ├── vad.rs            # RMS-based speech gate
    │   ├── denoise.rs        # FFT spectral gating
    │   └── pipeline.rs       # VAD state machine + chunk finalization
    ├── stt/
    │   ├── whisper_cli.rs    # subprocess backend
    │   ├── mlx_bridge.rs     # MLX-Whisper via .venv python
    │   └── prompts.rs        # hallucination stripping
    ├── llm/
    │   ├── mlx.rs            # MLX-LM bridge via .venv python
    │   └── prompts.rs        # translation prompt builder + validation
    └── state/
        └── mod.rs            # AppState, AppEvent, PublicState
```

## Known limitations / next steps

- **MLX backends** rely on the project's `.venv` Python being present at
  `<project>/.venv/bin/python` with `mlx-whisper` / `mlx-lm` installed.
- **Whisper.cpp** requires `/opt/homebrew/bin/whisper-cli` and the model files
  at `/opt/homebrew/share/whisper-cpp/models/`.
- **ScreenCaptureKit** requires macOS 13+ and a one-time Screen Recording
  permission grant. Foundry handles the TCC prompt the first time you press
  Record with System Audio selected.
- **Pure-Rust WebRTC VAD** is not implemented yet — the current RMS gate is
  functionally equivalent to the Python fallback (`is_frame_speech() or rms > 0.003`).
- **No code-signing** — the `.app` is unsigned. macOS will prompt on first
  launch; right-click → Open the first time, or run `xattr -dr com.apple.quarantine`
  to clear the Gatekeeper flag.