//! Audio pipeline orchestrator — owns the VAD state machine and the chunk
//! queue. Two capture sources can push mono f32 samples into it:
//!   1. `cpal` — microphone / virtual audio device (BlackHole etc.).
//!   2. ScreenCaptureKit — system audio on macOS 13+.
//!
//! Both sources send raw mono f32 blocks to an `async-channel`. The
//! pipeline's run loop reads blocks, feeds the shared VSM, and finalises
//! chunks for the STT stage.

use super::capture::{find_device_by_name, CaptureStream};
use super::denoise::denoise;
use super::vad::{chunk_has_speech, frame_rms, is_speech_frame};
use super::SYSTEM_AUDIO_DEVICE;
use crate::config::{BLOCK_DURATION, SAMPLE_RATE};
use crate::state::{AppEvent, AppState};
use async_channel::{Receiver, Sender};
use std::collections::VecDeque;
use std::time::{Duration, Instant};

const BLOCK_SAMPLES: usize =
    (SAMPLE_RATE as usize * BLOCK_DURATION.as_millis() as usize) / 1000;

/// Spawn the pipeline. Returns a handle exposing:
///   * `stop()` — graceful shutdown
///   * `chunks()` — channel of denoised mono f32 chunks for the STT task
pub fn spawn(state: AppState) -> PipelineHandle {
    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    let (chunk_tx, chunk_rx) = async_channel::bounded::<Vec<f32>>(64);
    let (sample_tx, sample_rx) = async_channel::bounded::<Vec<f32>>(512);

    let pipeline = Pipeline {
        state: state.clone(),
        stop: stop_rx,
        chunk_tx,
        sample_rx,
        sample_tx: sample_tx.clone(),
    };

    std::thread::Builder::new()
        .name("foundry-audio".into())
        .spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("audio runtime");
            rt.block_on(pipeline.run());
        })
        .expect("spawn audio thread");

    PipelineHandle {
        stop: stop_tx,
        chunks: chunk_rx,
        samples_in: sample_tx,
    }
}

#[derive(Clone)]
pub struct PipelineHandle {
    /// Signal the audio pipeline to shut down (gracefully).
    pub stop: tokio::sync::watch::Sender<bool>,
    /// Receiver of denoised mono f32 chunks for the STT stage.
    pub chunks: Receiver<Vec<f32>>,
    /// Capture sources push raw mono f32 blocks here. The pipeline drains
    /// from this channel on its run loop.
    #[allow(dead_code)]
    pub samples_in: Sender<Vec<f32>>,
}

impl PipelineHandle {
    /// Signal the pipeline to stop. Dropping the handle also stops it
    /// when the watch channel closes.
    #[allow(dead_code)]
    pub fn stop(&self) {
        let _ = self.stop.send(true);
    }
}

struct Pipeline {
    state: AppState,
    stop: tokio::sync::watch::Receiver<bool>,
    chunk_tx: Sender<Vec<f32>>,
    sample_rx: Receiver<Vec<f32>>,
    sample_tx: Sender<Vec<f32>>,
}

impl Pipeline {
    async fn run(mut self) {
        log::info!("audio pipeline started");

        let mut stream: Option<StreamHandle> = None;
        // When we've switched the system default output, remember the
        // original device ID so we can restore it when capture stops.
        // `None` when no switch has been performed (so we don't
        // accidentally restore to something the user changed
        // manually outside Foundry).
        let mut prev_output_id: Option<u32> = None;
        // Set after a Screen-Recording TCC denial. Auto-clear when
        // listening is toggled off, the device changes away from
        // the SCK pseudo-device, or the user requests a retry via
        // `state.audio_retry_signal` (the UI bumps this when the
        // user clicks "Open System Settings" on the permission
        // toast). While `true`, the SCK open attempt is silently
        // skipped (the friendly toast was already shown once) so
        // the user doesn't see the same error every second.
        let mut tcc_denied = false;
        // Last-seen `audio_retry_signal` value. When the snapshot
        // advances, we reset `tcc_denied` and drop `stream` so the
        // next iteration rebuilds — letting the user retry SCK
        // without toggling Listen off and back on.
        let mut last_retry_signal: u64 = self.state.snapshot().audio_retry_signal;
        let mut vsm = VadStateMachine::new(self.state.clone(), self.chunk_tx.clone());

        while !*self.stop.borrow() {
            let snap = self.state.snapshot();

            // Reconcile stream with current state.
            let target_open = snap.listening && !snap.device.is_empty();
            let need_rebuild = match &stream {
                None => target_open,
                Some(s) => target_open && (s.device_name() != snap.device || s.output_target() != snap.output_device),
            };

            if !target_open {
                if stream.take().is_some() {
                    log::info!("capture stopped");
                    // Restore the original system default output if we
                    // switched it for this recording session.
                    #[cfg(target_os = "macos")]
                    if let Some(id) = prev_output_id.take() {
                        if let Err(e) = super::output::set_default_output_device(id) {
                            log::warn!("failed to restore original output device (id={id}): {e}");
                        } else {
                            log::info!("restored original system output");
                        }
                    }
                    self.state.emit(AppEvent::State(Box::new(self.state.snapshot())));
                }
                // Reset TCC-denial state whenever listening is off (or
                // the device became empty). The next Listen-on will
                // re-attempt SCK, in case the user granted permission
                // in System Settings while listening was off.
                tcc_denied = false;
            } else if need_rebuild {
                // If the user switched away from the SCK pseudo-device,
                // clear the TCC flag — the previous denial doesn't
                // apply to whatever they're capturing now.
                if snap.device != SYSTEM_AUDIO_DEVICE {
                    tcc_denied = false;
                }

                // Audio-retry signal: the UI bumps this when the user
                // clicks "Open System Settings" on the permission toast
                // (or any other future "retry capture" affordance).
                // Reset the TCC latch and let the rebuild proceed — no
                // need for the user to toggle Listen off and back on.
                if snap.audio_retry_signal != last_retry_signal {
                    last_retry_signal = snap.audio_retry_signal;
                    if tcc_denied {
                        log::info!(
                            "audio retry requested (signal={}); resetting TCC latch",
                            snap.audio_retry_signal
                        );
                        tcc_denied = false;
                        // Force the stream to rebuild even if it
                        // somehow matched.
                        stream = None;
                    }
                }

                // After a Screen-Recording denial, skip the open loop
                // entirely. The friendly toast already explained what
                // to do; we don't need to re-emit it (and don't need
                // the 1-second wait per failed attempt to feel like
                // spam). The flag resets when the user toggles Listen
                // off and on, switches devices, or requests a retry.
                if tcc_denied {
                    tokio::time::sleep(Duration::from_millis(500)).await;
                    continue;
                }

                stream = None; // drop old before opening new
                // Restore any prior output switch before potentially
                // switching again — covers the case where the user
                // changes the output dropdown while recording.
                #[cfg(target_os = "macos")]
                if let Some(id) = prev_output_id.take() {
                    let _ = super::output::set_default_output_device(id);
                }

                // Switch the system default output to the user's
                // selection before opening SCK. SCK captures the
                // system mix, so the audio needs to be playing
                // through the selected device for us to record it.
                #[cfg(target_os = "macos")]
                {
                    let target_name = snap.output_device.clone();
                    let want_switch = !target_name.is_empty();
                    if want_switch {
                        match super::output::get_default_output_device() {
                            Ok(Some(current)) => {
                                if current.name != target_name {
                                    match super::output::find_id_by_name(&target_name) {
                                        Ok(Some(target_id)) => {
                                            match super::output::set_default_output_device(target_id) {
                                                Ok(()) => {
                                                    prev_output_id = Some(current.id);
                                                    self.state.emit(AppEvent::Info {
                                                        msg: format!(
                                                            "🔊 Routed system audio to {} (will restore on Stop)",
                                                            target_name
                                                        ),
                                                    });
                                                }
                                                Err(e) => {
                                                    self.state.emit(AppEvent::Error {
                                                        msg: format!(
                                                            "Could not switch output to {}: {}",
                                                            target_name, e
                                                        ),
                                                    });
                                                }
                                            }
                                        }
                                        _ => {
                                            self.state.emit(AppEvent::Error {
                                                msg: format!(
                                                    "Output '{}' not found in device list",
                                                    target_name
                                                ),
                                            });
                                        }
                                    }
                                }
                            }
                            Ok(None) => {
                                log::warn!("no current default output device");
                            }
                            Err(e) => {
                                log::warn!("failed to read default output: {e}");
                            }
                        }
                    }
                }

                let dev_name = snap.device.clone();
                let sample_tx = self.sample_rx_handle_for_source();
                match open_stream(&dev_name, &snap.output_device, self.state.clone(), sample_tx) {
                    Ok(s) => {
                        log::info!("opened capture on '{}'", s.device_name());
                        self.state.emit(AppEvent::Info {
                            msg: format!(
                                "🎧 Capturing from {} (dynamic VAD + denoise)",
                                s.device_name()
                            ),
                        });
                        stream = Some(s);
                    }
                    Err(super::system_capture::CaptureError::ScreenRecordingDenied) => {
                        // system_capture already emitted the friendly
                        // ErrorWithAction toast; just latch the flag
                        // and bail out of this rebuild attempt. The
                        // outer loop will keep spinning but skip the
                        // open call (via the `tcc_denied` early-return
                        // above) until the user toggles Listen.
                        tcc_denied = true;
                        #[cfg(target_os = "macos")]
                        if let Some(id) = prev_output_id.take() {
                            let _ = super::output::set_default_output_device(id);
                        }
                        tokio::time::sleep(Duration::from_millis(500)).await;
                        continue;
                    }
                    Err(e) => {
                        self.state.emit(AppEvent::Error {
                            msg: format!("Cannot open '{}': {}", dev_name, e),
                        });
                        // If we switched the output but the capture
                        // failed, restore the original so the user
                        // isn't left with a side effect from a failed
                        // recording.
                        #[cfg(target_os = "macos")]
                        if let Some(id) = prev_output_id.take() {
                            let _ = super::output::set_default_output_device(id);
                        }
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        continue;
                    }
                }
            }

            // Drain incoming samples from whichever source is active.
            loop {
                match self.sample_rx.try_recv() {
                    Ok(block) => {
                        if block.is_empty() {
                            continue;
                        }
                        vsm.feed(&block);
                    }
                    Err(async_channel::TryRecvError::Empty) => break,
                    Err(async_channel::TryRecvError::Closed) => {
                        log::warn!("sample channel closed");
                        break;
                    }
                }
            }

            tokio::select! {
                _ = self.stop.changed() => break,
                _ = tokio::time::sleep(Duration::from_millis(50)) => {},
            }
        }

        drop(stream);
        log::info!("audio pipeline stopped");
        let _ = self.chunk_tx.close();
    }

    /// Return a fresh sender that the capture source can push to. The
    /// pipeline drains from `self.sample_rx`; the sender we hand out is
    /// paired with that receiver via the bounded channel created in
    /// `spawn()`.
    fn sample_rx_handle_for_source(&self) -> Sender<Vec<f32>> {
        self.sample_tx.clone()
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Stream handle — either a cpal `CaptureStream` or a ScreenCaptureKit
// `SystemAudioCapture`.
// ─────────────────────────────────────────────────────────────────────────

enum StreamHandle {
    Cpal(CaptureStream),
    #[cfg(target_os = "macos")]
    System {
        // Held to keep the SCK capture session alive for the lifetime of
        // the stream handle. The struct itself doesn't expose state — it
        // spawns its own thread on `start()` — but dropping it stops
        // capture, so we must keep it in scope while the stream is open.
        #[allow(dead_code)]
        cap: super::SystemAudioCapture,
        /// Output device we routed system audio through when this
        /// stream was opened. `""` = left system default alone.
        output_target: String,
    },
}

impl StreamHandle {
    fn device_name(&self) -> String {
        match self {
            StreamHandle::Cpal(s) => s.device_name.clone(),
            #[cfg(target_os = "macos")]
            StreamHandle::System { .. } => SYSTEM_AUDIO_DEVICE.to_string(),
        }
    }

    #[cfg(target_os = "macos")]
    fn output_target(&self) -> &str {
        match self {
            StreamHandle::System { output_target, .. } => output_target.as_str(),
            _ => "",
        }
    }
}

fn open_stream(
    device_name: &str,
    output_target: &str,
    state: AppState,
    sample_tx: Sender<Vec<f32>>,
) -> Result<StreamHandle, super::system_capture::CaptureError> {
    if device_name.is_empty() {
        return Err(super::system_capture::CaptureError::Other(
            "no input device selected".into(),
        ));
    }

    // System audio path — ScreenCaptureKit.
    #[cfg(target_os = "macos")]
    if device_name == SYSTEM_AUDIO_DEVICE {
        let cap = super::SystemAudioCapture::start(state, sample_tx)?;
        return Ok(StreamHandle::System {
            cap,
            output_target: output_target.to_string(),
        });
    }

    // cpal path — microphone / BlackHole / etc.
    let device = match find_device_by_name(device_name) {
        Ok(d) => d,
        Err(e) => {
            return Err(super::system_capture::CaptureError::Other(format!(
                "{e}"
            )));
        }
    };
    let stream = match CaptureStream::open(&device, move |block: &[f32]| {
        // cpal invokes this on the audio thread; sample_tx is the
        // pipeline-side sender this closure captured by move.
        let _ = sample_tx.try_send(block.to_vec());
    }) {
        Ok(s) => s,
        Err(e) => {
            return Err(super::system_capture::CaptureError::Other(format!(
                "{e}"
            )));
        }
    };
    Ok(StreamHandle::Cpal(stream))
}

// ─────────────────────────────────────────────────────────────────────────
// VAD state machine — same logic as the previous implementation, but lives
// directly in the pipeline and holds the chunk sender inline.
// ─────────────────────────────────────────────────────────────────────────

struct VadStateMachine {
    state: AppState,
    chunk_tx: Sender<Vec<f32>>,
    pre_roll: VecDeque<Vec<f32>>,
    accumulated: Vec<Vec<f32>>,
    is_speaking: bool,
    speech_time: f32,
    silence_time: f32,
    continuous_silent_samples: usize,
    last_silent_warn: Instant,
}

impl VadStateMachine {
    fn new(state: AppState, chunk_tx: Sender<Vec<f32>>) -> Self {
        Self {
            state,
            chunk_tx,
            pre_roll: VecDeque::with_capacity(5),
            accumulated: Vec::new(),
            is_speaking: false,
            speech_time: 0.0,
            silence_time: 0.0,
            continuous_silent_samples: 0,
            last_silent_warn: Instant::now() - Duration::from_secs(60),
        }
    }

    fn feed(&mut self, block: &[f32]) {
        let snap = self.state.snapshot();
        let silence_threshold = snap.vad_silence_threshold;
        let max_speech = snap.vad_max_speech_duration;

        // Level meter.
        let rms = frame_rms(block);
        let vol_ui = (rms * 5.0).min(1.0);
        self.state.emit(AppEvent::Level { v: vol_ui });

        // Silence watchdog.
        let peak: f32 = block.iter().fold(0.0_f32, |a, s| a.max(s.abs()));
        if peak < 0.001 {
            self.continuous_silent_samples += block.len();
            if self.continuous_silent_samples >= SAMPLE_RATE as usize * 15 {
                if self.last_silent_warn.elapsed() > Duration::from_secs(30) {
                    let dev = snap.device.clone();
                    self.state.emit(AppEvent::Error {
                        msg: format!(
                            "🔇 No audio input on '{}' — system audio isn't routed here. \
                             For 'System Audio (ScreenCaptureKit)', grant Screen Recording \
                             permission in System Settings → Privacy & Security. \
                             For other devices, set '{}' as the OUTPUT in the source app \
                             (Teams/Zoom/browser), or create a Multi-Output Device in \
                             Audio MIDI Setup that sends to both your speakers and '{}'.",
                            dev, dev, dev
                        ),
                    });
                    self.last_silent_warn = Instant::now();
                }
                self.continuous_silent_samples = SAMPLE_RATE as usize * 15;
            }
        } else {
            self.continuous_silent_samples = 0;
        }

        // VAD.
        let is_speech = is_speech_frame(block) || rms > 0.003;
        let block_secs = block.len() as f32 / SAMPLE_RATE as f32;

        if is_speech {
            if !self.is_speaking {
                self.is_speaking = true;
                self.accumulated = self.pre_roll.drain(..).collect();
                self.speech_time = self.accumulated.len() as f32 * block_secs;
                self.silence_time = 0.0;
            }
            self.accumulated.push(block.to_vec());
            self.speech_time += block_secs;
            self.silence_time = 0.0;

            if self.speech_time >= max_speech {
                self.finalize_chunk();
            }
        } else if self.is_speaking {
            self.accumulated.push(block.to_vec());
            self.silence_time += block_secs;
            self.speech_time += block_secs;

            if self.silence_time >= silence_threshold || self.speech_time >= max_speech {
                self.finalize_chunk();
            }
        } else {
            if self.pre_roll.len() >= 5 {
                self.pre_roll.pop_front();
            }
            self.pre_roll.push_back(block.to_vec());
        }
    }

    fn finalize_chunk(&mut self) {
        if self.accumulated.is_empty() {
            self.is_speaking = false;
            return;
        }
        let total_len: usize = self.accumulated.iter().map(|v| v.len()).sum();
        let mut chunk = Vec::with_capacity(total_len);
        for v in &self.accumulated {
            chunk.extend_from_slice(v);
        }
        self.accumulated.clear();
        self.is_speaking = false;
        self.speech_time = 0.0;
        self.silence_time = 0.0;

        if !chunk_has_speech(&chunk) {
            return;
        }
        let cleaned = denoise(&chunk);
        let _ = self.chunk_tx.try_send(cleaned);
    }
}

#[allow(dead_code)]
const _: () = {
    assert!(BLOCK_SAMPLES == 1600);
};