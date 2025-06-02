use std::collections::HashMap;
use std::fs::File;
use std::sync::Mutex;

use fs2::FileExt;
use once_cell::sync::Lazy;

/// Global map of locked files (by path) to hold file handles across FFI calls.
static LOCK_MAP: Lazy<Mutex<HashMap<String, File>>> = Lazy::new(|| Mutex::new(HashMap::new()));

/// Blocking lock
#[flutter_rust_bridge::frb]
pub fn acquire_lock(path: String) -> Result<bool, String> {
    let file = File::create(&path).map_err(|e| e.to_string())?;
    file.lock_exclusive().map_err(|e| e.to_string())?;

    LOCK_MAP.lock().unwrap().insert(path, file);
    Ok(true)
}

/// Non-blocking lock
#[flutter_rust_bridge::frb]
pub fn try_acquire_lock(path: String) -> Result<bool, String> {
    let file = File::create(&path).map_err(|e| e.to_string())?;
    match file.try_lock_exclusive() {
        Ok(_) => {
            LOCK_MAP.lock().unwrap().insert(path, file);
            Ok(true)
        }
        Err(_) => Ok(false),
    }
}

/// Release a previously acquired lock 
#[flutter_rust_bridge::frb]
pub fn release_lock(path: String) -> Result<(), String> {
    let mut map = LOCK_MAP.lock().unwrap();
    if let Some(file) = map.remove(&path) {
        fs2::FileExt::unlock(&file).map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Check if the current process holds the lock
#[flutter_rust_bridge::frb]
pub fn is_lock_held(path: String) -> Result<bool, String> {
    Ok(LOCK_MAP.lock().unwrap().contains_key(&path))
}
