pub mod netease;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use netease::NetEaseClient;

/// Fetches lyrics from Netease Cloud Music.
/// Returns a heap-allocated JSON string pointer, or NULL on error / not found.
/// The caller is responsible for freeing the string using `CloudBeat_FreeLyricsString`.
#[no_mangle]
pub extern "C" fn CloudBeat_FetchNeteaseLyrics(
    title_ptr: *const c_char,
    artist_ptr: *const c_char,
    duration_ms: u64,
) -> *mut c_char {
    if title_ptr.is_null() || artist_ptr.is_null() {
        return std::ptr::null_mut();
    }

    let title = match unsafe { CStr::from_ptr(title_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let artist = match unsafe { CStr::from_ptr(artist_ptr) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(_) => return std::ptr::null_mut(),
    };

    let client = NetEaseClient::new();
    let duration_opt = if duration_ms > 0 { Some(duration_ms) } else { None };

    let result = rt.block_on(async {
        client.fetch_lyrics(title, artist, duration_opt).await
    });

    match result {
        Ok(Some(response)) => match serde_json::to_string(&response) {
            Ok(json_str) => match CString::new(json_str) {
                Ok(c_string) => c_string.into_raw(),
                Err(_) => std::ptr::null_mut(),
            },
            Err(_) => std::ptr::null_mut(),
        },
        _ => std::ptr::null_mut(),
    }
}

/// Frees a string previously allocated by `CloudBeat_FetchNeteaseLyrics`.
#[no_mangle]
pub extern "C" fn CloudBeat_FreeLyricsString(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}
