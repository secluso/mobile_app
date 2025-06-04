pub mod logger;
pub mod lock_manager;

use privastead_app_native::{self, Clients};

use std::collections::HashMap;
use std::sync::Mutex;
use log::info;

use std::net::SocketAddr;
use std::net::TcpStream;
use std::str::FromStr;

static CLIENTS: Mutex<Option<HashMap<String, Mutex<Option<Box<Clients>>>>>> = Mutex::new(None);

//good
#[flutter_rust_bridge::frb]
pub fn initialize_camera(camera_name: String, file_dir: String, first_time: bool) -> bool {
    let mut clients_map = CLIENTS.lock().unwrap();
    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        return match privastead_app_native::initialize(&mut *client_guard, file_dir, first_time) {
            Ok(_v) => return true,
            //TODO: Add back the error logging here
            Err(_e) => return false,
        };
    } else {
        info!("CLIENTS map not initialized!");
    }
    false
}

//TODO: Get rid of excess code
#[flutter_rust_bridge::frb]
pub fn deregister_camera(camera_name: String) {
    let mut clients_map_guard = CLIENTS.lock().unwrap();

    if let Some(map) = clients_map_guard.as_mut() {
        // Only proceed if the client exists
        if let Some(client_mutex) = map.get(&camera_name) {
            {
                // Start inner scope: lock, call deregister, then drop
                match client_mutex.lock() {
                    Ok(mut client_guard) => {
                        privastead_app_native::deregister(&mut *client_guard);
                    }
                    Err(poisoned) => {
                        info!("Mutex for {} was poisoned. Recovering.", camera_name);
                        let mut client_guard = poisoned.into_inner();
                        privastead_app_native::deregister(&mut *client_guard);
                    }
                }
            } // client_guard is dropped here

            if map.remove(&camera_name).is_none() {
                info!("Failed to remove {} from clients map", camera_name);
            }
        } else {
            info!("No client found for camera {}", camera_name);
        }
    } else {
        info!("CLIENTS map not initialized!");
    }
}

#[flutter_rust_bridge::frb]
pub fn decrypt_video(_camera_name: String, enc_filename: String) -> String {
    let mut clients_map = CLIENTS.lock().unwrap();
    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(_camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        match privastead_app_native::decrypt_video(&mut *client_guard, enc_filename) {
            Ok(decrypted_filename) => {
                return decrypted_filename;
            }
            Err(_e) => {
                return "Error!".to_string();
            }
        }
    } else {
        info!("CLIENTS map not initialized!");
        return "Error!".to_string();
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
) -> bool {
    let mut clients_map = CLIENTS.lock().unwrap();

    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        //TODO: Have this return a result, and then print the error (and return false)
        return privastead_app_native::add_camera(
            &mut *client_guard,
            camera_name,
            ip,
            secret,
            standalone,
            ssid,
            password,
        );
    } else {
        info!("CLIENTS map not initialized!");
    }

    false
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    logger::rust_set_up();
    info!("Setup logging correctly!");

    {
        let mut clients_map = CLIENTS.lock().unwrap();
        if clients_map.is_none() {
            *clients_map = Some(HashMap::new());
            info!("Initialized CLIENTS map");
        }
    }
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
pub fn decrypt_fcm_message(_camera_name: String, data: Vec<u8>) -> String {
    let mut clients_map = CLIENTS.lock().unwrap();
    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(_camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        match privastead_app_native::decrypt_fcm_message(&mut *client_guard, data) {
            Ok(timestamp) => {
                return timestamp;
            }
            Err(e) => {
                info!("Error: {}", e);
                return "Error!".to_string();
            }
        }
    } else {
        info!("CLIENTS map not initialized!");
        return "Error!".to_string();
    }
}

#[flutter_rust_bridge::frb]
pub fn get_motion_group_name(_camera_name: String) -> String {
    let mut clients_map = CLIENTS.lock().unwrap();
    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(_camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        match privastead_app_native::get_motion_group_name(&mut *client_guard, _camera_name) {
            Ok(motion_group_name) => {
                return motion_group_name;
            }
            Err(e) => {
                info!("Error: {}", e);
                return "Error!".to_string();
            }
        }
    } else {
        info!("CLIENTS map not initialized!");
        return "Error!".to_string();
    }
}

#[flutter_rust_bridge::frb]
pub fn livestream_update(_camera_name: String, msg: Vec<u8>) -> bool {
    let mut clients_map = CLIENTS.lock().unwrap();
    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(_camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        match privastead_app_native::livestream_update(&mut *client_guard, msg) {
            Ok(_) => {
                return true;
            }
            Err(e) => {
                info!("Error: {}", e);
                return false;
            }
        }
    } else {
        info!("CLIENTS map not initialized!");
        false
    }
}

#[flutter_rust_bridge::frb]
pub fn livestream_decrypt(_camera_name: String, data: Vec<u8>, expected_chunk_number: u64) -> Vec<u8> {
    let mut clients_map = CLIENTS.lock().unwrap();
    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(_camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        let ret = match privastead_app_native::livestream_decrypt(&mut *client_guard, data, expected_chunk_number) {
            Ok(dec_data) => dec_data,
            Err(e) => {
                info!("Error: {}", e);
                vec![]
            }
        };

        ret
    } else {
        info!("CLIENTS map not initialized!");
        vec![]
    }
}

//TODO: Fix all the _camera_names (get rid of leading _)
#[flutter_rust_bridge::frb]
pub fn get_livestream_group_name(_camera_name: String) -> String {
    let mut clients_map = CLIENTS.lock().unwrap();
    if let Some(map) = clients_map.as_mut() {
        let client_entry = map
            .entry(_camera_name.clone())
            .or_insert_with(|| Mutex::new(None));
        let mut client_guard = client_entry.lock().unwrap();

        match privastead_app_native::get_livestream_group_name(&mut *client_guard, _camera_name) {
            Ok(livestream_group_name) => {
                return livestream_group_name;
            }
            Err(e) => {
                info!("Error: {}", e);
                return "Error!".to_string();
            }
        }
    } else {
        info!("CLIENTS map not initialized!");
        return "Error!".to_string();
    }
}
