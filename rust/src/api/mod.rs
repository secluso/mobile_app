//! SPDX-License-Identifier: GPL-3.0-or-later

pub mod logger;
pub mod lock_manager;

use secluso_app_native::{self, Clients};

use std::collections::HashMap;
use parking_lot::Mutex;
use log::{info, error};
use once_cell::sync::Lazy;

use std::net::SocketAddr;
use std::net::TcpStream;
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::panic;

static CLIENTS: Lazy<Mutex<Option<HashMap<String, Arc<Mutex<Option<Box<Clients>>>>>>>> = Lazy::new(|| Mutex::new(None));
static IS_SHUTTING_DOWN: Lazy<AtomicBool> = Lazy::new(|| AtomicBool::new(false));

fn get_or_create_client_mutex(camera_name: &str) -> Arc<Mutex<Option<Box<Clients>>>> {
    let mut guard = CLIENTS.lock();
    let map = guard.get_or_insert_with(HashMap::new);
    map.entry(camera_name.to_owned())
        .or_insert_with(|| Arc::new(Mutex::new(None)))
        .clone() // clone the Arc so we can drop the map lock now
}

#[flutter_rust_bridge::frb]
pub fn initialize_camera(camera_name: String, file_dir: String, first_time: bool) -> bool {
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

    return match secluso_app_native::initialize(&mut *client_guard, file_dir, first_time) {
        Ok(_v) => return true,
        //TODO: Add back the error logging here
        Err(_e) => return false,
    };

    false
}

#[flutter_rust_bridge::frb]
pub fn deregister_camera(camera_name: String) {
    let client_arc_opt: Option<Arc<Mutex<Option<Box<Clients>>>>> = {
        let guard = CLIENTS.lock();
        guard
            .as_ref()
            .and_then(|map| map.get(&camera_name).cloned())
    };

    let Some(client_arc) = client_arc_opt else {
        info!("No client found for camera {}", camera_name);
        return;
    };

    let res = panic::catch_unwind(panic::AssertUnwindSafe(|| {
        let mut client_guard = client_arc.lock();
        secluso_app_native::deregister(&mut *client_guard);

        *client_guard = None;
    }));
    if res.is_err() {
        error!("Panic while deregistering camera {}", camera_name);
    }

    let mut guard = CLIENTS.lock();
    if let Some(map) = guard.as_mut() {
        let should_remove = match map.get(&camera_name) {
            Some(current_arc) if Arc::ptr_eq(current_arc, &client_arc) => true,
            _ => false,
        };
        if should_remove {
            if map.remove(&camera_name).is_none() {
                info!("Failed to remove {} from clients map", camera_name);
            }
        } else {
            info!(
                "Skipped removing {}: map entry changed while deregistering",
                camera_name
            );
        }
    } else {
        info!("CLIENTS map not initialized!");
    }
}

#[flutter_rust_bridge::frb]
pub fn decrypt_video(camera_name: String, enc_filename: String) -> String {
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

    match secluso_app_native::decrypt_video(&mut *client_guard, enc_filename) {
        Ok(decrypted_filename) => {
            return decrypted_filename;
        }
        Err(_e) => {
            return "Error".to_string();
        }
    }
}


#[flutter_rust_bridge::frb]
pub fn decrypt_thumbnail(camera_name: String, enc_filename: String, pending_meta_directory: String) -> String {
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

    match secluso_app_native::decrypt_thumbnail(&mut *client_guard, enc_filename, pending_meta_directory) {
        Ok(decrypted_filename) => {
            return decrypted_filename;
        }
        Err(_e) => {
            return "Error".to_string();
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
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

    //TODO: Have this return a result, and then print the error (and return false)
    return secluso_app_native::add_camera(
        &mut *client_guard,
        camera_name,
        ip,
        secret,
        standalone,
        ssid,
        password,
        pairing_token,
        credentials_full,
    );

    "Error".to_string()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    logger::rust_set_up();
    info!("Setup logging correctly!");

    {
        let mut clients_map = CLIENTS.lock();
        if clients_map.is_none() {
            *clients_map = Some(HashMap::new());
            info!("Initialized CLIENTS map");
        }
    }
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
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

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
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

    match secluso_app_native::decrypt_message(&mut *client_guard, &client_tag, data) {
        Ok(timestamp) => {
            return timestamp;
        }
        Err(e) => {
            info!("Error: {}", e);
            return "Error".to_string();
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn get_group_name(client_tag: String, camera_name: String) -> String {
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

    match secluso_app_native::get_group_name(&mut *client_guard, &client_tag) {
        Ok(motion_group_name) => {
            return motion_group_name;
        }
        Err(e) => {
            info!("Error: {}", e);
            return "Error".to_string();
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn livestream_update(camera_name: String, msg: Vec<u8>) -> bool {
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

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
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

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
pub fn generate_heartbeat_request_config_command(camera_name: String, timestamp: u64) -> Vec<u8> {
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

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
    let client_mutex = get_or_create_client_mutex(&camera_name);
    let mut client_guard = client_mutex.lock();

    match secluso_app_native::process_heartbeat_config_response(&mut *client_guard, config_response, expected_timestamp) {
        Ok(heartbeat_response) => {
            return heartbeat_response;
        }
        Err(e) => {
            info!("Error: {}", e);
            return "Error".to_string();
        }
    }
}
