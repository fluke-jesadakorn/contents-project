//! CoreAudio output device control — list output devices, read the
//! current default output, and switch it programmatically.
//!
//! Used by the audio pipeline to redirect all system audio to the
//! user-selected speaker (e.g., "Steam Streaming Speakers") before
//! opening the ScreenCaptureKit system-mix capture, and restore the
//! previous default when capture stops.
//!
//! ## API survival note
//!
//! On macOS 26, several CoreAudio HAL property queries return garbage:
//!
//! - `kAudioHardwarePropertyDevices` — returns a nonsense OSStatus
//!   (~0x6E5F5F25). Apple changed the contract.
//! - `kAudioDevicePropertyDeviceName` — returns packed C string in the
//!   out buffer instead of a `CFStringRef`. Incompatible with our FFI
//!   binding.
//! - `kAudioDevicePropertyStreams` (output scope) — also broken.
//!
//! What still works:
//!
//! - `kAudioObjectPropertyName` — returns a real `CFStringRef`. ✅
//! - `kAudioHardwarePropertyDefaultOutputDevice` GET and SET. ✅
//!
//! Strategy: use `cpal` to enumerate output devices (works), then
//! for each name iterate device IDs 1..MAX and query
//! `kAudioObjectPropertyName` to find the matching `AudioDeviceID`.
//! For SET we hand the ID directly to the working default-output
//! setter.

use anyhow::{anyhow, Result};
use std::ffi::{c_char, c_void, CString};
use std::os::raw::c_int;

/// Output device descriptor. The `id` is the CoreAudio `AudioDeviceID`
/// (a `UInt32`) — needed to set the device as default.
#[derive(Debug, Clone)]
pub struct OutputDevice {
    pub id: u32,
    pub name: String,
}

// ─── CoreAudio FFI ─────────────────────────────────────────────────────────

#[repr(C)]
#[derive(Debug, Clone, Copy)]
struct AudioObjectPropertyAddress {
    selector: u32,
    scope: u32,
    element: u32,
}

const K_AUDIO_OBJECT_SYSTEM_OBJECT: u32 = 1;
const K_AUDIO_OBJECT_PROPERTY_SCOPE_GLOBAL: u32 = 0x676C6F62; // 'glob'
const K_AUDIO_HARDWARE_PROPERTY_DEFAULT_OUTPUT_DEVICE: u32 = 0x64657621; // 'dev!'
const K_AUDIO_OBJECT_PROPERTY_NAME: u32 = 0x6E616D65; // 'name'

type OSStatus = i32;

#[link(name = "CoreAudio", kind = "framework")]
#[link(name = "CoreFoundation", kind = "framework")]
// `#[link]` attributes are additive — we need one per framework, but the
// `kind = "framework"` modifier is a shared shape across them. Clippy's
// `duplicated_attributes` lint flags it anyway because the modifier
// token is repeated. Each framework genuinely needs its own link attr.
#[allow(clippy::duplicated_attributes)]
extern "C" {
    /// The C signature is:
    ///
    /// ```c
    /// OSStatus AudioObjectGetPropertyData(
    ///     AudioObjectID inObjectID,
    ///     const AudioObjectPropertyAddress *inAddress,
    ///     UInt32 inQualifierDataSize,
    ///     const void *inQualifierData,
    ///     UInt32 *ioDataSize,
    ///     void *outData);
    /// ```
    ///
    /// 6 parameters. Pass `0` and `NULL` for the qualifier pair when
    /// the property doesn't require qualification.
    fn AudioObjectGetPropertyData(
        in_object_id: u32,
        in_address: *const AudioObjectPropertyAddress,
        in_qualifier_data_size: u32,
        in_qualifier_data: *const c_void,
        io_data_size: *mut u32,
        out_data: *mut c_void,
    ) -> OSStatus;

    fn AudioObjectSetPropertyData(
        in_object_id: u32,
        in_address: *const AudioObjectPropertyAddress,
        in_qualifier_data_size: u32,
        in_qualifier_data: *const c_void,
        in_data_size: u32,
        in_data: *const c_void,
    ) -> OSStatus;

    // CFString — opaque pointer; we only need `CFStringGetCString` to
    // read the bytes into a Rust-owned buffer.
    fn CFStringGetCString(
        the_string: *const c_void,
        buffer: *mut c_char,
        buffer_size: c_int,
        encoding: u32,
    ) -> u8; // Bool
}

// kCFStringEncodingUTF8 — declared as 0x08000100 in CoreFoundation.
const K_CF_STRING_ENCODING_UTF8: u32 = 0x0800_0100;

/// Maximum device ID we probe when looking up a name. Real Macs
/// don't go much past ~200; this is conservative.
const MAX_DEVICE_ID_PROBE: u32 = 512;

// ─── Public API ────────────────────────────────────────────────────────────

/// Enumerate all output devices. Uses `cpal` for the canonical list
/// of output-only devices (cpal's `output_devices()` works on macOS
/// 26; CoreAudio's `kAudioHardwarePropertyDevices` does not — see
/// module-level note). The `id` field on each entry is `None` here;
/// use `find_id_by_name` to get it on demand.
pub fn list_output_devices() -> Result<Vec<OutputDevice>> {
    use cpal::traits::{DeviceTrait, HostTrait};
    let host = cpal::default_host();
    let mut out = Vec::new();
    for dev in host.output_devices().map_err(|e| anyhow!("cpal output_devices: {e}"))? {
        let name = dev.name().unwrap_or_else(|_| String::new());
        if name.is_empty() {
            continue;
        }
        // `id` placeholder — cpal doesn't expose AudioDeviceID. Use
        // `find_id_by_name` to resolve when we actually need it.
        out.push(OutputDevice { id: 0, name });
    }
    Ok(out)
}

/// Find the CoreAudio `AudioDeviceID` for a given device name by
/// iterating IDs 1..MAX and querying `kAudioObjectPropertyName`.
/// Returns `Ok(None)` if not found.
pub fn find_id_by_name(name: &str) -> Result<Option<u32>> {
    for id in 1..=MAX_DEVICE_ID_PROBE {
        // Quick reject: query name. If the function fails, this ID
        // is invalid (no device with this id) — skip.
        match get_object_name(id) {
            Ok(Some(this_name)) if this_name == name => return Ok(Some(id)),
            Ok(_) => continue,
            Err(_) => continue,
        }
    }
    Ok(None)
}

/// Read the system's current default output device.
pub fn get_default_output_device() -> Result<Option<OutputDevice>> {
    let address = AudioObjectPropertyAddress {
        selector: K_AUDIO_HARDWARE_PROPERTY_DEFAULT_OUTPUT_DEVICE,
        scope: K_AUDIO_OBJECT_PROPERTY_SCOPE_GLOBAL,
        element: 0,
    };
    let mut id: u32 = 0;
    let mut size = std::mem::size_of::<u32>() as u32;
    let status = unsafe {
        AudioObjectGetPropertyData(
            K_AUDIO_OBJECT_SYSTEM_OBJECT,
            &address,
            0,
            std::ptr::null(),
            &mut size,
            &mut id as *mut u32 as *mut c_void,
        )
    };
    if status != 0 {
        return Err(anyhow!("get default output: OSStatus {status}"));
    }
    if id == 0 {
        return Ok(None);
    }
    let name = get_object_name(id)?.unwrap_or_else(|| format!("device-{id}"));
    Ok(Some(OutputDevice { id, name }))
}

/// Set the system's default output device. Affects all apps' audio
/// routing until something else changes it.
pub fn set_default_output_device(id: u32) -> Result<()> {
    let address = AudioObjectPropertyAddress {
        selector: K_AUDIO_HARDWARE_PROPERTY_DEFAULT_OUTPUT_DEVICE,
        scope: K_AUDIO_OBJECT_PROPERTY_SCOPE_GLOBAL,
        element: 0,
    };
    let status = unsafe {
        AudioObjectSetPropertyData(
            K_AUDIO_OBJECT_SYSTEM_OBJECT,
            &address,
            0,
            std::ptr::null(),
            std::mem::size_of::<u32>() as u32,
            &id as *const u32 as *const c_void,
        )
    };
    if status != 0 {
        return Err(anyhow!(
            "set default output (id={id}) failed with OSStatus {status}"
        ));
    }
    Ok(())
}

// ─── Internals ─────────────────────────────────────────────────────────────

/// Read `kAudioObjectPropertyName` for an arbitrary AudioObjectID.
/// Returns `Ok(None)` if the object doesn't exist or has no name.
/// Returns `Err` only on a real CoreAudio error (rare).
fn get_object_name(id: u32) -> Result<Option<String>> {
    let address = AudioObjectPropertyAddress {
        selector: K_AUDIO_OBJECT_PROPERTY_NAME,
        scope: K_AUDIO_OBJECT_PROPERTY_SCOPE_GLOBAL,
        element: 0,
    };
    let mut cfstring: *const c_void = std::ptr::null();
    let mut size = std::mem::size_of::<*const c_void>() as u32;
    let status = unsafe {
        AudioObjectGetPropertyData(
            id,
            &address,
            0,
            std::ptr::null(),
            &mut size,
            &mut cfstring as *mut *const c_void as *mut c_void,
        )
    };
    if status != 0 || cfstring.is_null() {
        return Ok(None);
    }
    // CFStringGetCString copies into our buffer with a known
    // encoding. 512 bytes is plenty for any device name we care
    // about (max observed in the wild is ~120 chars).
    let mut buf = vec![0u8; 512];
    let ok = unsafe {
        CFStringGetCString(
            cfstring,
            buf.as_mut_ptr() as *mut c_char,
            buf.len() as c_int,
            K_CF_STRING_ENCODING_UTF8,
        )
    };
    if ok == 0 {
        return Err(anyhow!("CFStringGetCString failed for device {id}"));
    }
    let len = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    Ok(Some(String::from_utf8_lossy(&buf[..len]).trim().to_string()))
}

/// Unused — kept for parity with prior version. The deprecated
/// `kAudioHardwarePropertyDevices` enumeration is broken on macOS
/// 26 (returns a garbage OSStatus); use `list_output_devices()`
/// (cpal) + `find_id_by_name()` (CoreAudio by-id loop) instead.
#[allow(dead_code)]
fn _unused_cstring_marker(_: CString) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_output_devices_does_not_panic() {
        // Uses cpal — works on macOS 26.
        let res = list_output_devices();
        assert!(res.is_ok(), "list_output_devices failed: {:?}", res.err());
        for d in res.unwrap() {
            assert!(!d.name.is_empty(), "device has empty name: {:?}", d);
        }
    }

    #[test]
    fn get_default_output_device_round_trip() {
        let res = get_default_output_device();
        assert!(res.is_ok());
    }

    #[test]
    fn find_id_by_name_finds_current_default() {
        // Get current default name, look it up by iterating IDs.
        let current = get_default_output_device().unwrap();
        if let Some(dev) = current {
            let id = find_id_by_name(&dev.name).unwrap();
            assert_eq!(id, Some(dev.id), "roundtrip id mismatch for {}", dev.name);
        }
    }
}
