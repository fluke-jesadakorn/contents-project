//! Device / host detection — chip, RAM, cores, OS, MLX-readiness.
//!
//! Pure-shell `sysctl` + `sw_vers` lookups. We avoid `system_profiler`
//! (multi-second latency) and the Metal `objc2` bindings for the same
//! reason — this runs on every app boot.
//!
//! The detection is one-shot: results are cached in `AppState` for the
//! lifetime of the process. If the user plugs in a different Mac, they
//! need to relaunch.

use serde::{Deserialize, Serialize};
use std::process::Command;

/// Detected host specs. `None` if detection failed.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DeviceSpecs {
    /// Raw `machdep.cpu.brand_string` — e.g. `"Apple M2 Pro"` or
    /// `"Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"`.
    pub chip_raw: String,
    /// Short chip label: `"M2 Pro"`, `"M4 Max"`, `"Intel i7-9750H"`,
    /// or the raw string if it doesn't match a known pattern.
    pub chip_short: String,
    /// Total physical memory in bytes (from `hw.memsize`).
    pub total_memory_bytes: u64,
    /// Physical CPU cores (`hw.physicalcpu`).
    pub physical_cpus: u32,
    /// Logical CPU cores (`hw.logicalcpu`).
    pub logical_cpus: u32,
    /// macOS product version, e.g. `"14.5"`.
    pub os_version: String,
    /// `true` when `chip_short` starts with `"M"` + digit (M1/M2/M3/M4
    /// and their Pro/Max/Ultra variants). MLX-LM and MLX-Whisper only
    /// run on these.
    pub is_apple_silicon: bool,
}

/// Run sysctl/sw_vers to snapshot the host. Best-effort: any failure
/// yields a partial struct rather than an Err — we want the UI to
/// render *something* even on a non-macOS dev box.
pub fn detect_device() -> DeviceSpecs {
    let chip_raw = sysctl_str("machdep.cpu.brand_string")
        .unwrap_or_else(|| "Unknown CPU".to_string());
    let chip_short = shorten_chip_name(&chip_raw);
    let is_apple_silicon = is_apple_silicon(&chip_short);
    let total_memory_bytes = sysctl_u64("hw.memsize").unwrap_or(0);
    let physical_cpus = sysctl_u32("hw.physicalcpu").unwrap_or(0);
    let logical_cpus = sysctl_u32("hw.logicalcpu").unwrap_or(0);
    let os_version = read_os_version();
    DeviceSpecs {
        chip_raw,
        chip_short,
        total_memory_bytes,
        physical_cpus,
        logical_cpus,
        os_version,
        is_apple_silicon,
    }
}

fn sysctl_str(key: &str) -> Option<String> {
    let out = Command::new("sysctl").arg("-n").arg(key).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn sysctl_u64(key: &str) -> Option<u64> {
    sysctl_str(key)?.trim().parse().ok()
}

fn sysctl_u32(key: &str) -> Option<u32> {
    sysctl_str(key)?.trim().parse().ok()
}

fn read_os_version() -> String {
    Command::new("sw_vers")
        .arg("-productVersion")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "macOS ?".to_string())
}

/// Map the raw `machdep.cpu.brand_string` to a short label suitable
/// for the toolbar / device card.
///
/// `"Apple M2 Pro"` → `"M2 Pro"`, `"Apple M4 Max"` → `"M4 Max"`,
/// `"Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"` → `"Intel i7-9750H"`.
fn shorten_chip_name(raw: &str) -> String {
    let trimmed = raw.trim();
    if let Some(rest) = trimmed.strip_prefix("Apple ") {
        return rest.to_string();
    }
    // Intel: pull "i7-9750H" or similar out of the verbose string.
    if let Some(idx) = trimmed.find("Core(TM) ") {
        let after = &trimmed[idx + "Core(TM) ".len()..];
        // After "Core(TM) " we have e.g. "i7-9750H CPU @ ..."
        let model: String = after
            .chars()
            .take_while(|c| !c.is_whitespace() || *c == '-')
            .take_while(|c| *c != 'C') // stop before "CPU"
            .collect();
        let model = model.trim_end_matches(' ').trim_end_matches('C').trim();
        if !model.is_empty() {
            return format!("Intel {model}");
        }
    }
    trimmed.to_string()
}

fn is_apple_silicon(chip_short: &str) -> bool {
    // Matches M1/M2/M3/M4 followed by optional variant (Pro/Max/Ultra)
    // or nothing. M5+ when they ship will continue to match.
    let mut chars = chip_short.chars();
    matches!((chars.next(), chars.next()), (Some('M'), Some(c)) if c.is_ascii_digit())
}

/// Pretty-print a byte count. `"4.2 GB"`, `"750 MB"`, `"12 KB"`.
pub fn format_bytes(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    const TB: u64 = GB * 1024;
    if bytes >= TB {
        format!("{:.1} TB", bytes as f64 / TB as f64)
    } else if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.0} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.0} KB", bytes as f64 / KB as f64)
    } else {
        format!("{bytes} B")
    }
}

/// Estimate the peak unified-memory footprint of an MLX model given
/// its on-disk size and an optional quantization hint.
///
/// MLX keeps weights quantized during compute (no dequant-to-fp16
/// step), so the dominant memory consumer is the file size itself.
/// The only meaningful add-ons are:
///
///   * **KV cache** — proportional to context length. For a
///     translation workload with ~4k context and ~512 tokens of
///     output, this is on the order of 0.3–0.8 GB for a 4-bit 8B
///     model.
///   * **Activations / Metal scratch buffers** — typically a few
///     hundred MB at most for short sequences.
///
/// We add a flat 15% overhead for 4-bit and 20% for everything
/// else (bf16/fp16 models keep the same ratio but their file
/// size already dominates, so 15% is plenty). These are rough
/// estimates — actual peak depends on `max_tokens` and the prompt
/// length — but they're accurate enough to flag "this won't
/// load" before the user waits 10 minutes for a download.
pub fn estimate_vram_bytes(file_size_bytes: u64, quant: Option<&str>) -> u64 {
    let overhead = match quant {
        Some(q) if q.contains("4-bit") || q.contains("4bit") => 1.15,
        // 2/3/5/6/8-bit and anything else gets a slightly larger
        // overhead for the dequant/activation buffers.
        _ => 1.20,
    };
    (file_size_bytes as f64 * overhead) as u64
}

/// Whether a model of `estimated_bytes` will comfortably fit in
/// `total_memory_bytes` (the Mac's unified memory).
///
/// Bands (LM Studio-style):
///   * `Fits`     — comfortable headroom for KV cache + OS
///   * `Tight`    — within ~15% of the cap; expect noticeable
///     swap pressure and slow first-token latency
///   * `WontFit`  — over the cap; the MLX loader will fail or
///     push aggressively into swap
///   * `Unknown`  — we don't know the device's total memory
///     (e.g. detection failed at boot)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FitStatus {
    Fits,
    Tight,
    WontFit,
    Unknown,
}

impl FitStatus {
    /// User-facing short label for the chip / pill rendering.
    pub fn label(self) -> &'static str {
        match self {
            FitStatus::Fits => "Fits",
            FitStatus::Tight => "Tight",
            FitStatus::WontFit => "Won't fit",
            FitStatus::Unknown => "Unknown",
        }
    }

    /// CSS class hook for the row renderer.
    pub fn css_class(self) -> &'static str {
        match self {
            FitStatus::Fits => "fit-ok",
            FitStatus::Tight => "fit-tight",
            FitStatus::WontFit => "fit-bad",
            FitStatus::Unknown => "fit-unknown",
        }
    }
}

pub fn fit_status(estimated_bytes: u64, total_memory_bytes: u64) -> FitStatus {
    if total_memory_bytes == 0 {
        return FitStatus::Unknown;
    }
    let ratio = estimated_bytes as f64 / total_memory_bytes as f64;
    if ratio < 0.85 {
        FitStatus::Fits
    } else if ratio < 1.0 {
        FitStatus::Tight
    } else {
        FitStatus::WontFit
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apple_silicon_detection() {
        assert!(is_apple_silicon("M1"));
        assert!(is_apple_silicon("M2"));
        assert!(is_apple_silicon("M2 Pro"));
        assert!(is_apple_silicon("M3 Max"));
        assert!(is_apple_silicon("M4 Ultra"));
        assert!(!is_apple_silicon("Intel i7-9750H"));
        assert!(!is_apple_silicon(""));
        assert!(!is_apple_silicon("AMD Ryzen 7"));
    }

    #[test]
    fn shorten_apple_chips() {
        assert_eq!(shorten_chip_name("Apple M1"), "M1");
        assert_eq!(shorten_chip_name("Apple M2 Pro"), "M2 Pro");
        assert_eq!(shorten_chip_name("Apple M4 Max"), "M4 Max");
        assert_eq!(shorten_chip_name("Apple M4 Ultra"), "M4 Ultra");
    }

    #[test]
    fn shorten_intel_chips() {
        assert_eq!(
            shorten_chip_name("Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"),
            "Intel i7-9750H"
        );
        assert_eq!(
            shorten_chip_name("Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz"),
            "Intel i9-9980HK"
        );
    }

    #[test]
    fn format_bytes_units() {
        assert_eq!(format_bytes(0), "0 B");
        assert_eq!(format_bytes(512), "512 B");
        assert_eq!(format_bytes(2048), "2 KB");
        assert_eq!(format_bytes(5 * 1024 * 1024), "5 MB");
        assert_eq!(format_bytes(4_500_000_000), "4.2 GB");
        assert_eq!(format_bytes(2 * 1024 * 1024 * 1024 * 1024), "2.0 TB");
    }

    #[test]
    fn detect_device_returns_something() {
        // Smoke test — should never panic on any host.
        let specs = detect_device();
        // On macOS the chip_raw is non-empty and we got a brand string.
        // On other hosts it falls back to "Unknown CPU".
        assert!(!specs.chip_raw.is_empty());
        assert!(!specs.chip_short.is_empty());
        // RAM might be 0 on non-macOS but should be > 0 in CI / dev.
        // Don't assert; just exercise the path.
        let _ = specs.total_memory_bytes;
    }

    // ─── VRAM estimation ────────────────────────────────────────

    /// 4 GB 4-bit model on a 48 GB Mac → ~4.6 GB estimate.
    #[test]
    fn estimate_vram_4bit_uses_15pct_overhead() {
        let file = 4 * 1024 * 1024 * 1024_u64; // 4 GB
        let est = estimate_vram_bytes(file, Some("4-bit"));
        // 4 * 1.15 = 4.6 GB
        assert_eq!(est, (4.6 * 1024.0 * 1024.0 * 1024.0) as u64);
    }

    /// Unknown quant falls back to the larger overhead.
    #[test]
    fn estimate_vram_unknown_quant_uses_20pct() {
        let file = 4 * 1024 * 1024 * 1024_u64;
        let est = estimate_vram_bytes(file, None);
        // 4 * 1.20 = 4.8 GB
        assert_eq!(est, (4.8 * 1024.0 * 1024.0 * 1024.0) as u64);
    }

    /// "4bit" without hyphen (HF naming variant) is recognised.
    #[test]
    fn estimate_vram_handles_4bit_no_hyphen() {
        let file = 8 * 1024 * 1024 * 1024_u64;
        let with_hyphen = estimate_vram_bytes(file, Some("4-bit"));
        let no_hyphen = estimate_vram_bytes(file, Some("4bit"));
        assert_eq!(with_hyphen, no_hyphen);
    }

    #[test]
    fn fit_status_bands() {
        let mem = 48 * 1024 * 1024 * 1024_u64; // 48 GB
        // 30 GB / 48 GB = 0.625 → Fits
        assert_eq!(fit_status(30 * 1024_u64.pow(3), mem), FitStatus::Fits);
        // 44 GB / 48 GB = 0.917 → Tight
        assert_eq!(fit_status(44 * 1024_u64.pow(3), mem), FitStatus::Tight);
        // 60 GB / 48 GB = 1.25 → WontFit
        assert_eq!(fit_status(60 * 1024_u64.pow(3), mem), FitStatus::WontFit);
        // 40.7 GB / 48 GB = 0.848 → Fits (boundary at 0.85)
        assert_eq!(fit_status((40.8 * 1024.0 * 1024.0 * 1024.0) as u64, mem), FitStatus::Fits);
        // 0 RAM → Unknown
        assert_eq!(fit_status(1024, 0), FitStatus::Unknown);
    }

    #[test]
    fn fit_status_label_and_class_are_stable() {
        // The CSS class is part of the render contract — changing it
        // silently would break the stylesheet. Lock it down.
        assert_eq!(FitStatus::Fits.label(), "Fits");
        assert_eq!(FitStatus::Tight.label(), "Tight");
        assert_eq!(FitStatus::WontFit.label(), "Won't fit");
        assert_eq!(FitStatus::Fits.css_class(), "fit-ok");
        assert_eq!(FitStatus::Tight.css_class(), "fit-tight");
        assert_eq!(FitStatus::WontFit.css_class(), "fit-bad");
        assert_eq!(FitStatus::Unknown.css_class(), "fit-unknown");
    }

    /// Realistic case: Llama 3.1 8B 4-bit on a 48 GB M3 Max.
    /// File size from HF ≈ 4.5 GB; estimate ≈ 5.2 GB; Fits.
    #[test]
    fn realistic_llama31_8b_4bit_on_m3_max_48gb() {
        let file = (4.5 * 1024.0 * 1024.0 * 1024.0) as u64;
        let est = estimate_vram_bytes(file, Some("4-bit"));
        let mem = 48 * 1024_u64.pow(3);
        assert_eq!(fit_status(est, mem), FitStatus::Fits);
        // Sanity: the estimate should round to "5.2 GB" in display.
        assert_eq!(format_bytes(est), "5.2 GB");
    }

    /// Realistic case: Llama 3.1 70B 4-bit on a 48 GB Mac.
    /// File size ≈ 40 GB; estimate ≈ 46 GB; Tight.
    #[test]
    fn realistic_llama31_70b_4bit_on_48gb_is_tight() {
        let file = (40.0 * 1024.0 * 1024.0 * 1024.0) as u64;
        let est = estimate_vram_bytes(file, Some("4-bit"));
        let mem = 48 * 1024_u64.pow(3);
        // 40 * 1.15 = 46 GB on 48 GB → ratio 0.958 → Tight
        assert_eq!(fit_status(est, mem), FitStatus::Tight);
    }
}
