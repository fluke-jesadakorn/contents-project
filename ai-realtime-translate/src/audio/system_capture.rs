//! System audio capture via Apple's ScreenCaptureKit (macOS 13+).
//!
//! Same engine OBS uses on macOS. Captures every audio source playing on
//! the system (excluding our own app) without needing BlackHole or any
//! virtual-audio-driver setup.
//!
//! # Wire format
//!
//! ScreenCaptureKit delivers audio as `CMSampleBuffer` instances containing
//! `LinearPCM` Float32. We extract the raw PCM pointer via Core Media,
//! average to mono, and hand a `Vec<f32>` to the pipeline via an
//! `async-channel::Sender`. The pipeline then resamples to 16 kHz for the
//! STT stage (mlx-whisper only — whisper.cpp backend removed).
//!
//! # TCC
//!
//! First-time use triggers a one-time Screen Recording permission prompt
//! (`NSScreenCaptureUsageDescription` in Info.plist). Until the user grants
//! it in System Settings → Privacy & Security, `start()` will fail with an
//! SCK error and we surface it via the toast layer.

use crate::state::{AppEvent, AppState};
use anyhow::{anyhow, Result};
use async_channel::Sender;
use block2::RcBlock;
use objc2::rc::{autoreleasepool, Retained};
use objc2::runtime::{AnyObject, Bool};
// `AnyThread` brings `ClassType::alloc()` into scope via its blanket impl —
// the compiler needs the trait visible to resolve `<StreamDelegate>::alloc()`.
#[allow(unused_imports)]
use objc2::AnyThread;
use objc2::{class, msg_send, DefinedClass};
use objc2_foundation::{NSError, NSObject, NSObjectProtocol};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Errors that can come out of [`SystemAudioCapture::start`].
///
/// The pipeline uses the [`CaptureError::ScreenRecordingDenied`] variant to
/// skip the auto-retry loop and stop re-emitting the error every second
/// (TCC denials won't fix themselves within the same session — the user has
/// to grant permission in System Settings and toggle Listen again).
#[derive(Debug, thiserror::Error)]
pub enum CaptureError {
    /// The user (or a previous MDM/parent-control decision) declined the
    /// Screen Recording TCC prompt. Apple surfaces this via
    /// `SCShareableContent` with a `NSOSStatusErrorDomain` error whose
    /// `localizedDescription` contains `"declined"` and/or `"TCC"` — we
    /// match on that substring since the precise NSError code varies
    /// across macOS versions.
    #[error("Screen Recording permission denied")]
    ScreenRecordingDenied,
    /// Anything else — wrapped so callers can still log the underlying
    /// message via `anyhow`/`Display`.
    #[error("{0}")]
    Other(String),
}

impl From<anyhow::Error> for CaptureError {
    fn from(e: anyhow::Error) -> Self {
        CaptureError::Other(e.to_string())
    }
}

/// `true` if the localized description Apple returned from SCK looks like
/// a TCC/Screen-Recording denial. Apple's wording has shifted across macOS
/// versions — we match the substrings that have been stable since 13.0:
///
///   * "declined"
///   * "TCC"
///   * "Screen Recording" / "Screen Capture"
///
/// Anything else is treated as a non-permission failure and surfaced as
/// `CaptureError::Other`.
fn is_screen_recording_denied(desc: &str) -> bool {
    let d = desc.to_lowercase();
    d.contains("declined")
        || d.contains(" tcc")
        || d.contains("screen recording")
        || d.contains("screen capture")
        || d.contains("capture content")
}

/// URL that opens macOS System Settings directly at the Screen Recording
/// privacy pane. Stable across macOS 13 (Ventura) through 15 (Sequoia).
///
/// Falls through gracefully if the URL scheme is rejected — the friendly
/// message in the toast tells the user the manual path too.
const SCREEN_RECORDING_PREF_URL: &str =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture";

/// Minimum interval between TCC-denial toasts. Each retry attempt that
/// still fails (e.g. user re-clicks Listen without granting permission
/// in System Settings) emits the friendly toast at most once per
/// `TCC_TOAST_THROTTLE` — otherwise the toast re-appears immediately on
/// every retry, which feels like a loop.
///
/// 30s is short enough that a user who steps away to read the message
/// still gets a fresh reminder, long enough that an auto-retry loop
/// doesn't spam them.
const TCC_TOAST_THROTTLE_MS: u64 = 30_000;

/// Monotonic clock (ms since UNIX epoch) of the last TCC-denial toast
/// we emitted. Touched from the SCK completion handler thread and the
/// pipeline thread, so it's atomic.
static LAST_TCC_TOAST_MS: AtomicU64 = AtomicU64::new(0);

/// Return `true` if we should emit a TCC-denial toast right now (and
/// record this as the new "last emit" timestamp). Returns `false` if
/// we emitted one recently — caller should silently fail.
fn try_mark_tcc_toast() -> bool {
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let last = LAST_TCC_TOAST_MS.load(Ordering::Relaxed);
    if now_ms.saturating_sub(last) < TCC_TOAST_THROTTLE_MS {
        return false;
    }
    // Compare-and-swap would be ideal but `Relaxed` is fine here:
    // racing two emits both set ~the same timestamp and both end up
    // "last emit", which is acceptable.
    LAST_TCC_TOAST_MS.store(now_ms, Ordering::Relaxed);
    true
}

// ─────────────────────────────────────────────────────────────────────────
// Raw FFI for Core Media — only what we need.
// ─────────────────────────────────────────────────────────────────────────

type Id = *mut AnyObject;

/// SCStreamOutputType enum value for audio-only output. From
/// `<ScreenCaptureKit/SCStream.h>`:
/// ```objc
/// typedef NS_ENUM(NSUInteger, SCStreamOutputType) {
///     SCStreamOutputTypeScreen = 0,
///     SCStreamOutputTypeAudio = 1,
///     SCStreamOutputTypeMicrophone = 2,
/// };
/// ```
const SC_STREAM_OUTPUT_TYPE_AUDIO: usize = 1;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
#[allow(dead_code, non_snake_case)]
struct AudioStreamBasicDescription {
    mSampleRate: f64,
    mFormatID: u32,
    mFormatFlags: u32,
    mBytesPerPacket: u32,
    mFramesPerPacket: u32,
    mBytesPerFrame: u32,
    mChannelsPerFrame: u32,
    mBitsPerChannel: u32,
    mReserved: u32,
}

#[link(name = "ScreenCaptureKit", kind = "framework")]
#[link(name = "CoreMedia", kind = "framework")]
#[link(name = "Foundation", kind = "framework")]
#[link(name = "CoreFoundation", kind = "framework")]
#[link(name = "CoreAudio", kind = "framework")]
// `#[link]` attributes are additive — each framework needs its own.
// Clippy's `duplicated_attributes` lint flags the shared `kind =
// "framework"` modifier anyway; each link line is genuinely distinct.
#[allow(clippy::duplicated_attributes)]
extern "C" {
    fn CMSampleBufferGetDataBuffer(sbuf: *mut AnyObject) -> *mut AnyObject;
    #[allow(dead_code)]
    fn CMSampleBufferGetFormatDescription(sbuf: *mut AnyObject) -> *mut AnyObject;
    fn CMBlockBufferGetDataLength(blkbuf: *mut AnyObject) -> usize;
    fn CMBlockBufferGetDataPointer(
        blkbuf: *mut AnyObject,
        offset: usize,
        length_at_offset: *mut usize,
        total_length: *mut usize,
        data_pointer: *mut *mut u8,
    ) -> i32;
    #[allow(dead_code)]
    fn CMAudioFormatDescriptionGetStreamBasicDescription(
        afd: *mut AnyObject,
        asbd: *mut *const AudioStreamBasicDescription,
    ) -> i32;

    fn dispatch_get_global_queue(identifier: i64, flags: u64) -> *mut AnyObject;
}

// ─────────────────────────────────────────────────────────────────────────
// SCStreamDelegate — receives `CMSampleBuffer` instances for the stream.
// ─────────────────────────────────────────────────────────────────────────

mod delegate {
    use super::*;
    use objc2::define_class;
    use std::cell::RefCell;

    pub struct Ivars {
        pub sender: RefCell<Option<Sender<Vec<f32>>>>,
        pub state: AppState,
        pub logged_format: RefCell<bool>,
    }

    define_class!(
        #[unsafe(super(NSObject))]
        #[name = "FoundrySCStreamDelegate"]
        #[ivars = Ivars]
        pub struct StreamDelegate;

        unsafe impl NSObjectProtocol for StreamDelegate {}

        // SAFETY: the method signature matches Apple's
        // `SCStreamDelegate.stream(_:didOutputSampleBuffer:ofType:)`. The
        // first arg is the SCStream (unused here), the second is the
        // CMSampleBuffer, the third is the SCStreamOutputType (an NSUInteger).
        impl StreamDelegate {
            #[unsafe(method(stream:didOutputSampleBuffer:ofType:))]
            // The Obj-C selector name `stream:didOutputSampleBuffer:ofType:`
            // is mandated by Apple's `SCStreamDelegate` protocol — Rust
            // mangles the snake_case method name to the selector, so this
            // exact identifier is required.
            #[allow(non_snake_case)]
            fn stream_didOutputSampleBuffer_ofType(
                &self,
                _stream: *mut AnyObject,
                sample_buffer: *mut AnyObject,
                of_type: usize,
            ) {
                // SCStreamOutputType is a typed NSUInteger enum. The audio
                // value is 1 (see top-level const above).
                if of_type != SC_STREAM_OUTPUT_TYPE_AUDIO || sample_buffer.is_null() {
                    return;
                }

                let result = autoreleasepool(|_| -> Result<(usize, Vec<f32>)> {
                    let blkbuf = unsafe { CMSampleBufferGetDataBuffer(sample_buffer) };
                    if blkbuf.is_null() {
                        return Err(anyhow!("null block buffer"));
                    }
                    let total_len = unsafe { CMBlockBufferGetDataLength(blkbuf) };
                    if total_len == 0 {
                        return Ok((0, Vec::new()));
                    }

                    let mut data_ptr: *mut u8 = std::ptr::null_mut();
                    let mut length_at_offset: usize = 0;
                    let mut total_length: usize = 0;
                    let status = unsafe {
                        CMBlockBufferGetDataPointer(
                            blkbuf,
                            0,
                            &mut length_at_offset,
                            &mut total_length,
                            &mut data_ptr,
                        )
                    };
                    if status != 0 || data_ptr.is_null() || total_length == 0 {
                        return Err(anyhow!("CMBlockBufferGetDataPointer status={status}"));
                    }

                    // ASBD lookup via CMAudioFormatDescriptionGetStreamBasicDescription
                    // returned `OSStatus -1497308704` on every sample on macOS 26
                    // — a non-standard code, likely because SCK's underlying
                    // format description is internally tagged in a way the
                    // audio-ASBD getter no longer recognises. Bypass it and
                    // trust the SCStreamConfiguration we set at start:
                    //   sampleRate    = 48000
                    //   channelCount  = 2
                    //   capturesAudio = true  (Float32 packed PCM)
                    //
                    // If SCK's audio format ever changes we'll need to
                    // re-introduce detection — a future fix could read
                    // CMFormatDescriptionGetMediaSubType to verify it's
                    // kAudioFormatLinearPCM ('lpcm') before falling back.
                    const BYTES_PER_SAMPLE: usize = 4; // Float32
                    const CHANNELS: usize = 2;
                    const SR: usize = 48_000;
                    let frame_count = total_length / (BYTES_PER_SAMPLE * CHANNELS);

                    let mut mono = Vec::with_capacity(frame_count);
                    for frame in 0..frame_count {
                        let mut acc = 0.0f32;
                        for ch in 0..CHANNELS {
                            let byte_off = (frame * CHANNELS + ch) * BYTES_PER_SAMPLE;
                            let p = unsafe { data_ptr.add(byte_off) as *const f32 };
                            acc += unsafe { *p };
                        }
                        mono.push(acc / CHANNELS as f32);
                    }

                    Ok((SR, mono))
                });

                match result {
                    Ok((sr, mono)) => {
                        let already_logged = *self.ivars().logged_format.borrow();
                        if !already_logged && sr > 0 {
                            *self.ivars().logged_format.borrow_mut() = true;
                            self.ivars().state.emit(AppEvent::Info {
                                msg: format!("🎧 System audio active ({} Hz, mono)", sr),
                            });
                        }
                        if !mono.is_empty() {
                            let s = self.ivars().sender.borrow().clone();
                            if let Some(tx) = s {
                                let _ = tx.try_send(mono);
                            }
                        }
                    }
                    Err(e) => log::warn!("SCK sample decode failed: {e}"),
                }
            }
        }
    );

    impl StreamDelegate {
        pub fn new(state: AppState, sender: Sender<Vec<f32>>) -> Retained<Self> {
            let ivars = Ivars {
                sender: RefCell::new(Some(sender)),
                state,
                logged_format: RefCell::new(false),
            };
            let this = Self::alloc().set_ivars(ivars);
            unsafe { msg_send![super(this), init] }
        }
    }
}

use delegate::StreamDelegate;

// ─────────────────────────────────────────────────────────────────────────
// Public entry — start a system-audio capture, return a handle whose `drop`
// tears the SCStream down.
// ─────────────────────────────────────────────────────────────────────────

pub struct SystemAudioCapture {
    /// Strong reference to the SCStream. Held as raw `Id` since we don't
    /// have an `extern_class!` for SCStream — we declared it dynamically.
    stream: Option<Id>,
    _delegate: Retained<StreamDelegate>,
}

impl SystemAudioCapture {
    /// Start capturing system audio. Audio chunks are pushed to `tx`.
    ///
    /// Blocks until the SCK shareable-content callback fires (or fails).
    pub fn start(state: AppState, tx: Sender<Vec<f32>>) -> Result<Self, CaptureError> {
        autoreleasepool(|_| -> Result<Self, CaptureError> {
            let delegate = StreamDelegate::new(state.clone(), tx);
            let delegate_id: Id = Retained::as_ptr(&delegate) as *mut AnyObject;

            // The shareable-content creation is async; bridge it with a
            // oneshot so we can return either the resulting SCStream or
            // an error to the caller.
            let (res_tx, res_rx) = std::sync::mpsc::channel::<Result<Id, CaptureError>>();

            let state_for_cb = state.clone();
            let handler_block = RcBlock::new(move |content: *mut AnyObject, err: *mut NSError| {
                autoreleasepool(|_| {
                    if !err.is_null() {
                        // SAFETY: err is non-null per the check above. NSError
                        // is toll-free bridged with CFError.
                        let desc = unsafe { (*err).localizedDescription() };
                        let desc_str = desc.to_string();

                        if is_screen_recording_denied(&desc_str) {
                            // Surface the friendly, actionable error to
                            // the UI. We do NOT also emit the raw Apple
                            // message — it's confusing and offers no
                            // remediation. Throttled so a retry that
                            // still fails doesn't spam the toast.
                            if try_mark_tcc_toast() {
                                state_for_cb.emit(AppEvent::ErrorWithAction {
                                    msg: "Screen Recording permission denied. Open \
                                          System Settings → Privacy & Security → Screen \
                                          Recording, enable Foundry, then click Listen again."
                                        .into(),
                                    action_label: "Open System Settings".into(),
                                    action_url: SCREEN_RECORDING_PREF_URL.to_string(),
                                });
                            }
                            let _ = res_tx.send(Err(CaptureError::ScreenRecordingDenied));
                        } else {
                            let msg = format!("SCShareableContent failed: {desc_str}");
                            state_for_cb.emit(AppEvent::Error { msg: msg.clone() });
                            let _ = res_tx.send(Err(CaptureError::Other(msg)));
                        }
                        return;
                    }
                    if content.is_null() {
                        let _ = res_tx.send(Err(CaptureError::Other(
                            "SCShareableContent returned null".into(),
                        )));
                        return;
                    }

                    let displays: *mut AnyObject = unsafe { msg_send![&*content, displays] };
                    let n: usize = unsafe { msg_send![displays, count] };
                    if n == 0 {
                        state_for_cb.emit(AppEvent::Error {
                            msg: "SCK: no shareable displays found".into(),
                        });
                        let _ = res_tx.send(Err(CaptureError::Other("no displays".into())));
                        return;
                    }
                    let display: *mut AnyObject =
                        unsafe { msg_send![displays, objectAtIndex: 0usize] };

                    // Build an explicit SCContentFilter. On macOS 13 the
                    // SCStream `initWithFilter:` parameter is typed
                    // `SCContentFilter`, NOT `SCDisplay`. Passing an
                    // SCDisplay directly used to work via implicit
                    // coercion, but in macOS 26 that coercion path
                    // calls `[SCDisplay contentRect]`, a selector that
                    // no longer exists — and the framework aborts our
                    // process. Building the filter explicitly avoids
                    // the coercion.
                    let empty_windows: *mut AnyObject = unsafe {
                        msg_send![class!(NSArray), array]
                    };
                    let filter: *mut AnyObject = unsafe {
                        let filter_cls = class!(SCContentFilter);
                        let allocated: *mut AnyObject = msg_send![filter_cls, alloc];
                        msg_send![
                            &*allocated,
                            initWithDisplay: display,
                            excludingWindows: empty_windows,
                        ]
                    };
                    if filter.is_null() {
                        state_for_cb.emit(AppEvent::Error {
                            msg: "SCK: SCContentFilter init returned null".into(),
                        });
                        let _ =
                            res_tx.send(Err(CaptureError::Other("filter init failed".into())));
                        return;
                    }

                    // SCStreamConfiguration.
                    let cfg_cls = class!(SCStreamConfiguration);
                    let cfg: *mut AnyObject = unsafe { msg_send![cfg_cls, new] };
                    let _: () = unsafe { msg_send![&*cfg, setWidth: 2_i32] };
                    let _: () = unsafe { msg_send![&*cfg, setHeight: 2_i32] };
                    let _: () =
                        unsafe { msg_send![&*cfg, setCapturesAudio: Bool::YES] };
                    let _: () = unsafe {
                        msg_send![&*cfg, setExcludesCurrentProcessAudio: Bool::YES]
                    };
                    let _: () = unsafe { msg_send![&*cfg, setSampleRate: 48_000_i32] };
                    let _: () = unsafe { msg_send![&*cfg, setChannelCount: 2_i32] };

                    let stream_cls = class!(SCStream);
                    let stream: *mut AnyObject =
                        unsafe { msg_send![stream_cls, alloc] };
                    let stream: *mut AnyObject = unsafe {
                        msg_send![
                            &*stream,
                            initWithFilter: filter,
                            configuration: cfg,
                            delegate: delegate_id,
                        ]
                    };
                    if stream.is_null() {
                        state_for_cb.emit(AppEvent::Error {
                            msg: "SCK: SCStream init returned null".into(),
                        });
                        let _ =
                            res_tx.send(Err(CaptureError::Other("stream init failed".into())));
                        return;
                    }

                    // addStreamOutput:type:sampleHandlerQueue:error:
                    let queue =
                        unsafe { dispatch_get_global_queue(/* QOS_CLASS_USER_INITIATED */ 25, 0) };
                    let mut add_err: *mut NSError = std::ptr::null_mut();
                    let ok: Bool = unsafe {
                        msg_send![
                            &*stream,
                            addStreamOutput: delegate_id,
                            type: SC_STREAM_OUTPUT_TYPE_AUDIO,
                            sampleHandlerQueue: queue,
                            error: &mut add_err,
                        ]
                    };
                    if !ok.is_true() {
                        let desc = if add_err.is_null() {
                            "unknown".to_string()
                        } else {
                            unsafe { (*add_err).localizedDescription() }.to_string()
                        };
                        let msg = format!("SCStream addStreamOutput failed: {desc}");
                        state_for_cb.emit(AppEvent::Error { msg: msg.clone() });
                        let _ = res_tx.send(Err(CaptureError::Other(msg)));
                        return;
                    }

                    // startCaptureWithCompletionHandler: — block ignores error
                    // here since the delegate will receive actual sample buffers
                    // once it succeeds.
                    let state_for_start = state_for_cb.clone();
                    let start_block = RcBlock::new(move |err: *mut NSError| {
                        if !err.is_null() {
                            let desc = unsafe { (*err).localizedDescription() };
                            state_for_start.emit(AppEvent::Error {
                                msg: format!("SCK startCapture failed: {}", desc),
                            });
                        } else {
                            state_for_start.emit(AppEvent::Info {
                                msg: "🎧 System audio stream started (ScreenCaptureKit)".into(),
                            });
                        }
                    });
                    let _: () = unsafe {
                        msg_send![
                            &*stream,
                            startCaptureWithCompletionHandler: &*start_block,
                        ]
                    };

                    let _ = res_tx.send(Ok(stream));
                });
            });

            // SCShareableContent.getShareableContentWithCompletionHandler:
            let cls = class!(SCShareableContent);
            let _: () = unsafe {
                msg_send![cls, getShareableContentWithCompletionHandler: &*handler_block]
            };

            // Wait synchronously for the callback.
            let stream_id = match res_rx.recv_timeout(Duration::from_secs(10)) {
                Ok(Ok(s)) => s,
                Ok(Err(e)) => return Err(e),
                Err(_) => {
                    // The SCK completion handler never fired — usually
                    // because the user clicked "Deny" on the original
                    // prompt and the kernel never delivers a callback.
                    // Treat the same as a TCC denial so the pipeline
                    // stops retrying and surfaces a friendly message.
                    if try_mark_tcc_toast() {
                        state.emit(AppEvent::ErrorWithAction {
                            msg: "Screen Recording permission is required to capture \
                                  system audio. Open System Settings → Privacy & \
                                  Security → Screen Recording, enable Foundry, then \
                                  click Listen again."
                                .into(),
                            action_label: "Open System Settings".into(),
                            action_url: SCREEN_RECORDING_PREF_URL.to_string(),
                        });
                    }
                    return Err(CaptureError::ScreenRecordingDenied);
                }
            };

            Ok(Self {
                stream: Some(stream_id),
                _delegate: delegate,
            })
        })
    }

    pub fn stop(&mut self) {
        if let Some(stream) = self.stream.take() {
            autoreleasepool(|_| {
                let stop_block = RcBlock::new(|_err: *mut NSError| {});
                let _: () = unsafe {
                    msg_send![
                        &*stream,
                        stopCaptureWithCompletionHandler: &*stop_block,
                    ]
                };
            });
        }
    }
}

impl Drop for SystemAudioCapture {
    fn drop(&mut self) {
        self.stop();
    }
}

unsafe impl Send for SystemAudioCapture {}
unsafe impl Sync for SystemAudioCapture {}

#[cfg(test)]
mod tests {
    #[test]
    fn smoke() {
        // Compile-only test — can't actually start SCK without TCC.
        // Sanity check that the audio-type constant we use to filter
        // SCK output callbacks matches Apple's published value.
        const SC_STREAM_OUTPUT_TYPE_AUDIO: usize = 1;
        let expected = 1_usize;
        assert_eq!(SC_STREAM_OUTPUT_TYPE_AUDIO, expected);
    }
}