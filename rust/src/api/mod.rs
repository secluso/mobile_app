//! SPDX-License-Identifier: GPL-3.0-or-later

pub mod logger;
pub mod lock_manager;

use secluso_app_native::{self, Clients};

use std::collections::HashMap;
use parking_lot::{Mutex, MutexGuard};
use log::{info, error, warn};
use once_cell::sync::Lazy;

use std::net::SocketAddr;
use std::net::TcpStream;
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::panic;
use std::time::{Duration, Instant};

#[derive(Hash, Eq, PartialEq, Clone)]
struct ClientKey {
    camera: String,
    channel: String,
}

#[derive(Clone)]
struct InitParams {
    file_dir: String,
    first_time: bool,
}

static CLIENTS: Lazy<Mutex<HashMap<ClientKey, Arc<Mutex<Option<Box<Clients>>>>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static INIT_PARAMS: Lazy<Mutex<HashMap<String, InitParams>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
static IS_SHUTTING_DOWN: Lazy<AtomicBool> = Lazy::new(|| AtomicBool::new(false));

const CLIENT_LOCK_TIMEOUT: Duration = Duration::from_secs(8);
const CLIENT_LOCK_WARN: Duration = Duration::from_millis(250);
const CHANNEL_MOTION: &str = "motion";
const CHANNEL_THUMBNAIL: &str = "thumbnail";
const CHANNEL_FCM: &str = "fcm";
const CHANNEL_CONFIG: &str = "config";
const CHANNEL_LIVESTREAM: &str = "livestream";
const CHANNEL_SETUP: &str = "setup";

macro_rules! lock_client_or_return {
    ($client_mutex:expr, $camera_name:expr, $op:expr, $ret:expr) => {{
        let start = Instant::now();
        match $client_mutex.try_lock_for(CLIENT_LOCK_TIMEOUT) {
            Some(guard) => {
                let elapsed = start.elapsed();
                if elapsed >= CLIENT_LOCK_WARN {
                    warn!(
                        "Lock wait {:?} for {} on camera {}",
                        elapsed, $op, $camera_name
                    );
                }
                guard
            }
            None => {
                error!(
                    "Lock timeout after {:?} for {} on camera {}",
                    CLIENT_LOCK_TIMEOUT, $op, $camera_name
                );
                return $ret;
            }
        }
    }};
}

fn get_or_create_channel_mutex(
    camera_name: &str,
    channel: &str,
) -> Arc<Mutex<Option<Box<Clients>>>> {
    let mut guard = CLIENTS.lock();
    let key = ClientKey {
        camera: camera_name.to_owned(),
        channel: channel.to_owned(),
    };
    guard
        .entry(key)
        .or_insert_with(|| Arc::new(Mutex::new(None)))
        .clone()
}

fn lock_client<'a>(
    client_mutex: &'a Arc<Mutex<Option<Box<Clients>>>>,
    camera_name: &str,
    op: &str,
) -> Option<MutexGuard<'a, Option<Box<Clients>>>> {
    let start = Instant::now();
    match client_mutex.try_lock_for(CLIENT_LOCK_TIMEOUT) {
        Some(guard) => {
            let elapsed = start.elapsed();
            if elapsed >= CLIENT_LOCK_WARN {
                warn!(
                    "Lock wait {:?} for {} on camera {}",
                    elapsed, op, camera_name
                );
            }
            Some(guard)
        }
        None => {
            error!(
                "Lock timeout after {:?} for {} on camera {}",
                CLIENT_LOCK_TIMEOUT, op, camera_name
            );
            None
        }
    }
}

fn ensure_client_initialized(
    client_guard: &mut Option<Box<Clients>>,
    camera_name: &str,
    channel: &str,
) -> bool {
    if client_guard.is_some() {
        return true;
    }

    let params = {
        let guard = INIT_PARAMS.lock();
        guard.get(camera_name).cloned()
    };

    let Some(params) = params else {
        warn!(
            "No init params for camera {} (channel {})",
            camera_name, channel
        );
        return false;
    };

    match secluso_app_native::initialize(
        client_guard,
        params.file_dir,
        params.first_time,
    ) {
        Ok(_) => true,
        Err(e) => {
            info!(
                "initialize error for camera {} channel {}: {}",
                camera_name, channel, e
            );
            false
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn initialize_camera(camera_name: String, file_dir: String, first_time: bool) -> bool {
    {
        let mut guard = INIT_PARAMS.lock();
        guard.insert(
            camera_name.clone(),
            InitParams {
                file_dir: file_dir.clone(),
                first_time,
            },
        );
    }

    let channels = [
        CHANNEL_MOTION,
        CHANNEL_THUMBNAIL,
        CHANNEL_FCM,
        CHANNEL_CONFIG,
        CHANNEL_LIVESTREAM,
        CHANNEL_SETUP,
    ];

    let mut ok = true;
    for channel in channels {
        let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
        let op = format!("initialize_camera({})", channel);
        let mut client_guard = match lock_client(&client_mutex, &camera_name, &op) {
            Some(guard) => guard,
            None => {
                ok = false;
                continue;
            }
        };
        if client_guard.is_some() {
            continue;
        }
        if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
            ok = false;
        }
    }

    ok
}

#[flutter_rust_bridge::frb]
pub fn deregister_camera(camera_name: String) {
    let entries: Vec<(ClientKey, Arc<Mutex<Option<Box<Clients>>>>)> = {
        let guard = CLIENTS.lock();
        guard
            .iter()
            .filter(|(key, _)| key.camera == camera_name)
            .map(|(key, arc)| (key.clone(), arc.clone()))
            .collect()
    };

    if entries.is_empty() {
        info!("No client found for camera {}", camera_name);
        return;
    }

    let mut did_deregister = false;
    for (key, client_arc) in &entries {
        let op = format!("deregister_camera({})", key.channel);
        let mut client_guard = match lock_client(client_arc, &camera_name, &op) {
            Some(guard) => guard,
            None => {
                warn!(
                    "Deregister skipped for camera {} channel {} due to lock timeout",
                    camera_name, key.channel
                );
                continue;
            }
        };

        let res = panic::catch_unwind(panic::AssertUnwindSafe(|| {
            secluso_app_native::deregister(&mut *client_guard);
            *client_guard = None;
        }));

        if res.is_err() {
            error!(
                "Panic while deregistering camera {} channel {}",
                camera_name, key.channel
            );
        } else {
            did_deregister = true;
        }
    }

    if !did_deregister {
        warn!("Deregister skipped for camera {}", camera_name);
    }

    {
        let mut guard = CLIENTS.lock();
        guard.retain(|key, _| key.camera != camera_name);
    }
    {
        let mut guard = INIT_PARAMS.lock();
        guard.remove(&camera_name);
    }
}

#[flutter_rust_bridge::frb]
pub fn decrypt_video(
    camera_name: String,
    enc_filename: String,
    assumed_epoch: u64,
) -> String {
    let channel = CHANNEL_MOTION;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        "decrypt_video(motion)",
        "Error".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::decrypt_video(
        &mut *client_guard,
        enc_filename,
        assumed_epoch,
    ) {
        Ok(decrypted_filename) => {
            return decrypted_filename;
        }
        Err(_e) => {
            return format!("Error(decrypt_video): {}", _e);
        }
    }
}


#[flutter_rust_bridge::frb]
pub fn decrypt_thumbnail(
    camera_name: String,
    enc_filename: String,
    pending_meta_directory: String,
    assumed_epoch: u64,
) -> String {
    let channel = CHANNEL_THUMBNAIL;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        "decrypt_thumbnail(thumbnail)",
        "Error".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::decrypt_thumbnail(
        &mut *client_guard,
        enc_filename,
        pending_meta_directory,
        assumed_epoch,
    ) {
        Ok(decrypted_filename) => {
            return decrypted_filename;
        }
        Err(_e) => {
            return format!("Error(decrypt_thumbnail): {}", _e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn flutter_add_camera(
    camera_name: String,
    ip: String,
    secret: Vec<u8>,
    standalone: bool,
    ssid: String,
    password: String,
    pairing_token: String,
    credentials_full: String,
) -> String {
    let result = {
        let channel = CHANNEL_SETUP;
        let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
        let mut client_guard = lock_client_or_return!(
            client_mutex,
            &camera_name,
            "flutter_add_camera(setup)",
            "Error".to_string()
        );
        if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
            return "Error".to_string();
        }

        //TODO: Have this return a result, and then print the error (and return false)
        secluso_app_native::add_camera(
            &mut *client_guard,
            camera_name.clone(),
            ip,
            secret,
            standalone,
            ssid,
            password,
            pairing_token,
            credentials_full,
        )
    };

    if !result.starts_with("Error") {
        {
            let mut guard = INIT_PARAMS.lock();
            if let Some(params) = guard.get_mut(&camera_name) {
                params.first_time = false;
            }
        }

        let entries: Vec<Arc<Mutex<Option<Box<Clients>>>>> = {
            let guard = CLIENTS.lock();
            guard
                .iter()
                .filter(|(key, _)| {
                    key.camera == camera_name && key.channel != CHANNEL_SETUP
                })
                .map(|(_, arc)| arc.clone())
                .collect()
        };

        for entry in entries {
            match entry.try_lock_for(CLIENT_LOCK_TIMEOUT) {
                Some(mut guard) => {
                    *guard = None;
                }
                None => {
                    warn!(
                        "Lock timeout after {:?} for reset_clients on camera {}",
                        CLIENT_LOCK_TIMEOUT, camera_name
                    );
                }
            }
        }
    }

    result
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    logger::rust_set_up();
    info!("Setup logging correctly!");
}

#[flutter_rust_bridge::frb]
pub fn shutdown_app() {
    if IS_SHUTTING_DOWN.swap(true, Ordering::SeqCst) {
        info!("shutdown_app(): already shutting down");
        return;
    }

    if let Err(e) = logger::rust_shutdown() {
        error!("logger shutdown error: {e:?}");
    }

    // If there's ever a shtudown/cleanup function in the app_native layer,
    // we can call it here.

    info!("shutdown_app(): done");
}


#[flutter_rust_bridge::frb]
pub fn ping_proprietary_device(camera_ip: String) -> bool {
    info!("Pinging proprietary device");
    let addr = match SocketAddr::from_str(&(camera_ip + ":12348")) {
        Ok(a) => a,
        Err(e) => {
            info!("Error: invalid IP address: {e}");
            return false;
        }
    };

    match TcpStream::connect(&addr) {
        Ok(_) => true,
        Err(e) => {
            info!("Error: {e}");
            false
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn encrypt_settings_message(camera_name: String, data: Vec<u8>) -> Vec<u8> {
    let channel = CHANNEL_CONFIG;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        "encrypt_settings_message(config)",
        Vec::new()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return Vec::new();
    }

    match secluso_app_native::encrypt_settings_message(&mut *client_guard, data) {
        Ok(encrypted_message) => {
            return encrypted_message;
        }
        Err(e) => {
            info!("Error: {}", e);
            return Vec::new();
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn decrypt_message(client_tag: String, camera_name: String, data: Vec<u8>) -> String {
    let channel = client_tag.as_str();
    let op = format!("decrypt_message({})", channel);
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard =
        lock_client_or_return!(client_mutex, &camera_name, &op, "Error".to_string());
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::decrypt_message(&mut *client_guard, &client_tag, data) {
        Ok(timestamp) => {
            return timestamp;
        }
        Err(e) => {
            info!("decrypt_message error: {}", e);
            return format!("Error(decrypt_message): {}", e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn get_group_name(client_tag: String, camera_name: String) -> String {
    let channel = client_tag.as_str();
    let op = format!("get_group_name({})", channel);
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard =
        lock_client_or_return!(client_mutex, &camera_name, &op, "Error".to_string());
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::get_group_name(&mut *client_guard, &client_tag) {
        Ok(motion_group_name) => {
            return motion_group_name;
        }
        Err(e) => {
            info!("get_group_name error: {}", e);
            return format!("Error(get_group_name): {}", e);
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn livestream_update(camera_name: String, msg: Vec<u8>) -> bool {
    let channel = CHANNEL_LIVESTREAM;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard =
        lock_client_or_return!(client_mutex, &camera_name, "livestream_update(livestream)", false);
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return false;
    }

    match secluso_app_native::livestream_update(&mut *client_guard, msg) {
        Ok(_) => {
            return true;
        }
        Err(e) => {
            info!("Error: {}", e);
            return false;
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn livestream_decrypt(camera_name: String, data: Vec<u8>, expected_chunk_number: u64) -> Vec<u8> {
    let channel = CHANNEL_LIVESTREAM;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard =
        lock_client_or_return!(client_mutex, &camera_name, "livestream_decrypt(livestream)", vec![]);
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    let ret = match secluso_app_native::livestream_decrypt(&mut *client_guard, data, expected_chunk_number) {
        Ok(dec_data) => dec_data,
        Err(e) => {
            info!("Error: {}", e);
            vec![]
        }
    };

    ret
}

#[flutter_rust_bridge::frb]
pub fn rust_lib_version() -> String {
    return env!("CARGO_PKG_VERSION").to_string()
}

#[flutter_rust_bridge::frb]
pub fn generate_heartbeat_request_config_command(camera_name: String, timestamp: u64) -> Vec<u8> {
    let channel = CHANNEL_CONFIG;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        "generate_heartbeat_request_config_command(config)",
        vec![]
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return vec![];
    }

    let ret = match secluso_app_native::generate_heartbeat_request_config_command(&mut *client_guard, timestamp) {
        Ok(config_msg_enc) => config_msg_enc,
        Err(e) => {
            info!("Error: {}", e);
            vec![]
        }
    };

    ret
}

#[flutter_rust_bridge::frb]
pub fn process_heartbeat_config_response(camera_name: String, config_response: Vec<u8>, expected_timestamp: u64) -> String {
    let channel = CHANNEL_CONFIG;
    let client_mutex = get_or_create_channel_mutex(&camera_name, channel);
    let mut client_guard = lock_client_or_return!(
        client_mutex,
        &camera_name,
        "process_heartbeat_config_response(config)",
        "Error".to_string()
    );
    if !ensure_client_initialized(&mut *client_guard, &camera_name, channel) {
        return "Error".to_string();
    }

    match secluso_app_native::process_heartbeat_config_response(&mut *client_guard, config_response, expected_timestamp) {
        Ok(heartbeat_response) => {
            return heartbeat_response;
        }
        Err(e) => {
            info!("process_heartbeat_config_response error: {}", e);
            return format!("Error(process_heartbeat_config_response): {}", e);
        }
    }
}
