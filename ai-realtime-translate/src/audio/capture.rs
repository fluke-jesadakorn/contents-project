//! `cpal` audio capture — wraps the platform's input stream and converts to
//! mono f32 @ 16 kHz (the format Whisper expects).

use crate::config::{CAPTURE_CHANNELS, SAMPLE_RATE};
use anyhow::{anyhow, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, SampleFormat, Stream, StreamConfig};
use std::sync::Arc;

/// List all input devices the OS reports. We return the raw index + name +
/// default sample rate so the UI can populate the dropdown.
pub fn list_input_devices() -> Result<Vec<DeviceInfo>> {
    let host = cpal::default_host();
    let mut out = vec![];
    for (i, dev) in host.input_devices()?.enumerate() {
        let name = dev.name().unwrap_or_else(|_| format!("input-{}", i));
        let cfg = dev.default_input_config().ok();
        let (channels, sr) = match cfg {
            Some(c) => (c.channels() as u32, c.sample_rate().0 as f32),
            None => (0u32, 0.0f32),
        };
        out.push(DeviceInfo {
            index: i as i32,
            name,
            channels,
            sample_rate: sr,
        });
    }
    Ok(out)
}

#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub index: i32,
    pub name: String,
    pub channels: u32,
    pub sample_rate: f32,
}

/// Try to find a device by name (substring match — BlackHole 2ch etc.).
pub fn find_device_by_name(name: &str) -> Result<Device> {
    let host = cpal::default_host();
    let needle = name.to_lowercase();
    for dev in host.input_devices()? {
        let dev_name = dev.name().unwrap_or_default().to_lowercase();
        if dev_name.contains(&needle) {
            return Ok(dev);
        }
    }
    Err(anyhow!("input device '{}' not found", name))
}

/// RAII handle to a live input stream. Dropping stops the stream.
pub struct CaptureStream {
    // Kept alive to keep the cpal stream alive — dropping this stops
    // capture. Not read after construction; cpal's `play()` already
    // started it.
    #[allow(dead_code)]
    pub stream: Stream,
    pub device_name: String,
}

impl CaptureStream {
    /// Open a stream on `device` and invoke `on_block` with each mono f32
    /// block (size = SAMPLE_RATE * BLOCK_DURATION). The block is converted
    /// from whatever format the device gives us to mono f32 @ SAMPLE_RATE.
    pub fn open<F>(device: &Device, mut on_block: F) -> Result<Self>
    where
        F: FnMut(&[f32]) + Send + 'static,
    {
        let supported = device
            .supported_input_configs()
            .map_err(|e| anyhow!("supported_input_configs: {e}"))?;
        // Pick the first config that supports 16 kHz mono f32 if possible;
        // otherwise fall back to the device's default.
        let chosen = supported
            .filter(|c| c.channels() >= 1)
            .min_by_key(|c| {
                let sr_match = (c.min_sample_rate().0..=c.max_sample_rate().0)
                    .contains(&SAMPLE_RATE) as u32;
                (sr_match == 0) as u32 * 1_000_000 + c.channels() as u32 * 1000
                    + (c.sample_format() == SampleFormat::F32) as u32 * 100
            })
            .ok_or_else(|| anyhow!("no supported input config"))?;

        let target_sr = if chosen.min_sample_rate().0 <= SAMPLE_RATE
            && chosen.max_sample_rate().0 >= SAMPLE_RATE
        {
            SAMPLE_RATE
        } else {
            chosen.max_sample_rate().0
        };

        let config = StreamConfig {
            channels: CAPTURE_CHANNELS.min(chosen.channels()),
            sample_rate: cpal::SampleRate(target_sr),
            buffer_size: cpal::BufferSize::Fixed(2048),
        };

        let device_name = device.name().unwrap_or_else(|_| "input".into());
        let device_sr = target_sr;
        let in_channels = config.channels as usize;

        let stream = device.build_input_stream(
            &config,
            move |data: &[f32], _info: &cpal::InputCallbackInfo| {
                let mono = to_mono(data, in_channels);
                let mono = if device_sr != SAMPLE_RATE {
                    resample_linear(&mono, device_sr, SAMPLE_RATE)
                } else {
                    mono
                };
                on_block(&mono);
            },
            move |err| log::warn!("cpal stream error: {err}"),
            None,
        )?;

        stream.play()?;
        Ok(Self {
            stream,
            device_name,
        })
    }
}

impl Drop for CaptureStream {
    fn drop(&mut self) {
        log::info!("dropping capture stream on {}", self.device_name);
    }
}

/// Average all channels to mono. Stereo input is summed (BlackHole 2ch usually
/// has the same content on both channels when capturing system audio).
pub fn to_mono(input: &[f32], channels: usize) -> Vec<f32> {
    if channels <= 1 {
        return input.to_vec();
    }
    let n = input.len() / channels;
    let mut out = Vec::with_capacity(n);
    for frame in input.chunks_exact(channels) {
        let s: f32 = frame.iter().sum::<f32>() / channels as f32;
        out.push(s);
    }
    out
}

/// Quick-and-dirty linear resampler. Good enough for level metering; the
/// STT path uses the full sample-rate-matched buffer directly.
pub fn resample_linear(input: &[f32], from_sr: u32, to_sr: u32) -> Vec<f32> {
    if from_sr == to_sr || input.is_empty() {
        return input.to_vec();
    }
    let ratio = to_sr as f64 / from_sr as f64;
    let out_len = (input.len() as f64 * ratio) as usize;
    let mut out = Vec::with_capacity(out_len);
    for i in 0..out_len {
        let t = i as f64 / ratio;
        let i0 = t.floor() as usize;
        let i1 = (i0 + 1).min(input.len() - 1);
        let frac = (t - i0 as f64) as f32;
        out.push(input[i0] * (1.0 - frac) + input[i1] * frac);
    }
    out
}

/// Convert a captured f32 buffer into a serialised mono f32 PCM ready for
/// either denoise → STT or direct level-meter calculation.
#[allow(dead_code)]
pub fn to_mono_pcm(input: &[f32], channels: usize) -> Arc<Vec<f32>> {
    Arc::new(to_mono(input, channels))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stereo_to_mono_averages() {
        let stereo = vec![1.0, -1.0, 0.5, -0.5, 0.0, 0.0];
        let mono = to_mono(&stereo, 2);
        assert_eq!(mono, vec![0.0, 0.0, 0.0]);
    }

    #[test]
    fn resample_changes_length() {
        let input: Vec<f32> = (0..16000).map(|i| i as f32 / 16000.0).collect();
        let out = resample_linear(&input, 16000, 8000);
        assert_eq!(out.len(), 8000);
    }
}