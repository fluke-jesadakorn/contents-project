//! Spectral gating denoiser — pure Rust FFT implementation of the same idea as
//! `noisereduce` (stationary noise profile + spectral subtraction).
//!
//! Why not pull `noisereduce` from PyO3? Because we want a single static binary
//! with no Python at runtime (other than the optional MLX bridge).
//!
//! Algorithm:
//!   1. STFT the chunk (Hann window, 50 % overlap).
//!   2. Estimate noise from the lowest-energy 20 % of frames (assumes noise
//!      frames are more frequent than speech).
//!   3. Spectral subtraction: `mag_denoised = max(mag - alpha * noise_mag, beta * mag)`.
//!   4. Inverse STFT, overlap-add.
//!
//! This is faster than the Python implementation (RustFFT SIMD + no GIL) and
//! gives comparable quality for the SNR we care about (system audio → STT).

use num_complex::Complex;
use rustfft::FftPlanner;
use std::sync::Arc;

const WINDOW_SIZE: usize = 1024;
const HOP_SIZE: usize = 512;
const ALPHA: f32 = 2.5; // over-subtraction factor
const BETA: f32 = 0.05; // spectral floor (prevents musical noise)

/// Denoise a mono f32 chunk in-place-ish (returns new Vec).
pub fn denoise(samples: &[f32]) -> Vec<f32> {
    if samples.len() < WINDOW_SIZE * 2 {
        return samples.to_vec();
    }

    let mut planner = FftPlanner::<f32>::new();
    let fft = Arc::new(planner.plan_fft_forward(WINDOW_SIZE));
    let ifft = Arc::new(planner.plan_fft_inverse(WINDOW_SIZE));

    let window: Vec<f32> = (0..WINDOW_SIZE)
        .map(|i| 0.5 - 0.5 * ((2.0 * std::f32::consts::PI * i as f32) / (WINDOW_SIZE - 1) as f32).cos())
        .collect();

    // Pad input so the last frame fits.
    let pad_len = (WINDOW_SIZE - samples.len() % HOP_SIZE) % HOP_SIZE;
    let mut padded = samples.to_vec();
    padded.extend(std::iter::repeat_n(0.0, pad_len));

    // STFT.
    let n_frames = (padded.len() - WINDOW_SIZE) / HOP_SIZE + 1;
    let mut frames: Vec<Vec<Complex<f32>>> = Vec::with_capacity(n_frames);
    for i in 0..n_frames {
        let start = i * HOP_SIZE;
        let frame: Vec<Complex<f32>> = padded[start..start + WINDOW_SIZE]
            .iter()
            .zip(&window)
            .map(|(s, w)| Complex::new(s * w, 0.0))
            .collect();
        let mut buf = frame;
        fft.process(&mut buf);
        frames.push(buf);
    }

    // Noise estimate: average magnitude of the quietest 20 % of frames.
    let mut frame_powers: Vec<(usize, f32)> = frames
        .iter()
        .enumerate()
        .map(|(i, f)| {
            let p: f32 = f.iter().map(|c| c.norm_sqr()).sum::<f32>() / WINDOW_SIZE as f32;
            (i, p)
        })
        .collect();
    frame_powers.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
    let n_noise = (n_frames as f32 * 0.20).ceil() as usize;
    let mut noise_mag = vec![0.0_f32; WINDOW_SIZE];
    for &(i, _) in frame_powers.iter().take(n_noise.max(1)) {
        for (k, c) in frames[i].iter().enumerate() {
            noise_mag[k] += c.norm();
        }
    }
    if n_noise > 0 {
        for v in noise_mag.iter_mut() {
            *v /= n_noise as f32;
        }
    }

    // Spectral subtraction + reconstruction.
    let mut output = vec![0.0_f32; padded.len()];
    let mut window_sum = vec![0.0_f32; padded.len()];

    for (i, frame) in frames.iter_mut().enumerate() {
        for (k, c) in frame.iter_mut().enumerate() {
            let mag = c.norm();
            let new_mag = (mag - ALPHA * noise_mag[k]).max(BETA * mag);
            let phase = c.arg();
            *c = Complex::from_polar(new_mag, phase);
        }
        ifft.process(frame);
        let start = i * HOP_SIZE;
        for (j, c) in frame.iter().enumerate() {
            output[start + j] += c.re * window[j];
            window_sum[start + j] += window[j] * window[j];
        }
    }

    // Normalise by window sum (COLA).
    for (o, w) in output.iter_mut().zip(window_sum.iter()) {
        if *w > 1e-6 {
            *o /= *w;
        }
    }

    output.truncate(samples.len());
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn denoise_pure_tone_passes() {
        // A 1-second pure 440 Hz tone should survive denoise.
        let n = 16000;
        let signal: Vec<f32> = (0..n)
            .map(|i| 0.5 * (2.0 * std::f32::consts::PI * 440.0 * i as f32 / 16000.0).sin())
            .collect();
        let out = denoise(&signal);
        assert_eq!(out.len(), signal.len());
        let rms_in: f32 = (signal.iter().map(|x| x * x).sum::<f32>() / n as f32).sqrt();
        let rms_out: f32 = (out.iter().map(|x| x * x).sum::<f32>() / n as f32).sqrt();
        // The denoiser should not nuke the signal entirely.
        assert!(rms_out > 0.1 * rms_in, "rms_in={} rms_out={}", rms_in, rms_out);
    }
}