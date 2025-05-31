use rand::Rng;
use std::fs;
use std::fs::File;
use std::io;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::SocketAddr;
use std::net::TcpStream;
use std::str::FromStr;
use std::str;

use log::info;

use privastead_client_lib::pairing;
use privastead_client_lib::user::{Contact, KeyPackages, User};
use privastead_client_lib::video_net_info::{VideoNetInfo, VIDEONETINFO_SANITY};
use serde_json::json;

const NUM_RANDOM_CHARS: u8 = 16;

#[flutter_rust_bridge::frb]
pub struct Clients {
    client_motion: User,
    client_livestream: User,
    client_fcm: User,
    client_config: User,
}

//good
#[flutter_rust_bridge::frb]
impl Clients {
    pub fn new(
        app_motion_name: String,
        app_livestream_name: String,
        app_fcm_name: String,
        app_config_name: String,
        first_time: bool,
        file_dir: String,
    ) -> io::Result<Self> {
        info!("Clients new start");

        info!("Creating client motion");
        let mut client_motion = User::new(
            app_motion_name,
            first_time,
            file_dir.clone(),
            "motion".to_string(),
        )?;

        info!("Saving group state of client_motion");
        // Make sure the groups_state files are created in case we initialize again soon.
        client_motion.save_groups_state();

        info!("Creating client livestream");
        let mut client_livestream = User::new(
            app_livestream_name,
            first_time,
            file_dir.clone(),
            "livestream".to_string(),
        )?;

        client_livestream.save_groups_state();

        let mut client_fcm = User::new(
            app_fcm_name,
            first_time,
            file_dir.clone(),
            "fcm".to_string(),
        )?;

        client_fcm.save_groups_state();

        let mut client_config = User::new(
            app_config_name,
            first_time,
            file_dir.clone(),
            "config".to_string(),
        )?;

        client_config.save_groups_state();

        Ok(Self {
            client_motion,
            client_livestream,
            client_fcm,
            client_config,
        })
    }
}

//good
fn get_app_name(first_time: bool, file_dir: String, filename: String) -> String {
    let app_name = if first_time {
        let mut rng = rand::thread_rng();
        let aname: String = (0..NUM_RANDOM_CHARS)
            .map(|_| rng.sample(rand::distributions::Alphanumeric) as char)
            .collect();

        let mut file =
            fs::File::create(file_dir.clone() + "/" + &filename).expect("Could not create file");
        file.write_all(aname.as_bytes()).unwrap();
        file.flush().unwrap();
        file.sync_all().unwrap();

        aname
    } else {
        let file =
            fs::File::open(file_dir.clone() + "/" + &filename).expect("Cannot open file to send");
        let mut reader =
            BufReader::with_capacity(file.metadata().unwrap().len().try_into().unwrap(), file);
        let aname = reader.fill_buf().unwrap();

        String::from_utf8(aname.to_vec()).unwrap()
    };

    app_name
}

//good
fn write_varying_len(stream: &mut TcpStream, msg: &[u8]) -> io::Result<()> {
    // FIXME: is u64 necessary?
    let len = msg.len() as u64;
    let len_data = len.to_be_bytes();

    stream.write_all(&len_data)?;
    stream.write_all(msg)?;
    stream.flush()?;

    Ok(())
}

//good
fn read_varying_len(stream: &mut TcpStream) -> io::Result<Vec<u8>> {
    let mut len_data = [0u8; 8];
    stream.read_exact(&mut len_data)?;
    let len = u64::from_be_bytes(len_data);

    let mut msg = vec![0u8; len as usize];
    stream.read_exact(&mut msg)?;

    Ok(msg)
}

//good
fn perform_pairing_handshake(
    stream: &mut TcpStream,
    app_key_packages: KeyPackages,
    secret: [u8; pairing::NUM_SECRET_BYTES],
) -> io::Result<KeyPackages> {
    let pairing = pairing::App::new(secret, app_key_packages);
    let app_msg = pairing.generate_msg_to_camera();
    write_varying_len(stream, &app_msg)?;
    let camera_msg = read_varying_len(stream)?;
    let camera_key_packages = pairing.process_camera_msg(camera_msg);

    Ok(camera_key_packages)
}

//good
fn send_wifi_info(
    stream: &mut TcpStream,
    client: &mut User,
    group_name: String,
    wifi_ssid: String,
    wifi_password: String,
) -> io::Result<()> {
    let wifi_msg = json!({
        "ssid": wifi_ssid,
        "passphrase": wifi_password
    });
    info!("Sending wifi info {}", wifi_msg);
    let wifi_info_msg = match client.encrypt(&serde_json::to_vec(&wifi_msg)?, &group_name) {
        Ok(msg) => msg,
        Err(e) => {
            info!("Failed to encrypt SSID: {e}");
            return Err(e);
        }
    };
    info!("Before Wifi Msg Sent");
    write_varying_len(stream, &wifi_info_msg)?;
    info!("After Wifi Msg Sent");

    client.save_groups_state();

    Ok(())
}

//good
#[flutter_rust_bridge::frb]
fn pair_with_camera(
    stream: &mut TcpStream,
    app_motion_key_packages: KeyPackages,
    app_livestream_key_packages: KeyPackages,
    app_fcm_key_packages: KeyPackages,
    app_config_key_packages: KeyPackages,
    secret: [u8; pairing::NUM_SECRET_BYTES],
) -> io::Result<(
    KeyPackages,
    Vec<u8>,
    KeyPackages,
    Vec<u8>,
    KeyPackages,
    Vec<u8>,
    KeyPackages,
    Vec<u8>,
)> {
    let camera_motion_key_packages =
        perform_pairing_handshake(stream, app_motion_key_packages, secret)?;
    let camera_motion_welcome_msg = read_varying_len(stream)?;

    let camera_livestream_key_packages =
        perform_pairing_handshake(stream, app_livestream_key_packages, secret)?;
    let camera_livestream_welcome_msg = read_varying_len(stream)?;

    let camera_fcm_key_packages = perform_pairing_handshake(stream, app_fcm_key_packages, secret)?;
    let camera_fcm_welcome_msg = read_varying_len(stream)?;

    let camera_config_key_packages =
        perform_pairing_handshake(stream, app_config_key_packages, secret)?;
    let camera_config_welcome_msg = read_varying_len(stream)?;

    Ok((
        camera_motion_key_packages,
        camera_motion_welcome_msg,
        camera_livestream_key_packages,
        camera_livestream_welcome_msg,
        camera_fcm_key_packages,
        camera_fcm_welcome_msg,
        camera_config_key_packages,
        camera_config_welcome_msg,
    ))
}

//good
fn process_welcome_message(
    client: &mut User,
    contact: Contact,
    welcome_msg: Vec<u8>,
) -> io::Result<()> {
    client.process_welcome(contact, welcome_msg)?;
    client.save_groups_state();

    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn add_camera(
    clients_reg: &mut Option<Box<Clients>>,
    camera_name: String,
    camera_ip: String,
    secret_vec: Vec<u8>,
    standalone_camera: bool,
    wifi_ssid: String,
    wifi_password: String,
) -> bool {
    info!("Rust: add_camera method triggered");
    if clients_reg.is_none() {
        info!("Error: clients not initialized!");
        return false;
    }

    let clients = clients_reg.as_mut().unwrap();

    // Check for duplicate camera_name
    let name_used = [
        clients.client_motion.get_group_name(&camera_name),
        clients
            .client_livestream
            .get_group_name(&camera_name),
        clients.client_fcm.get_group_name(&camera_name),
        clients.client_config.get_group_name(&camera_name),
    ]
        .into_iter()
        .any(|res| res.is_ok());

    if name_used {
        info!("Error: camera_name used before!");
        return false;
    }

    if secret_vec.len() != pairing::NUM_SECRET_BYTES {
        info!("Error: incorrect number of bytes in secret!");
        return false;
    }

    let mut camera_secret = [0u8; pairing::NUM_SECRET_BYTES];
    camera_secret.copy_from_slice(&secret_vec[..]);

    // Connect to the camera
    let addr = match SocketAddr::from_str(&(camera_ip + ":12348")) {
        Ok(a) => a,
        Err(e) => {
            info!("Error: invalid IP address: {e}");
            return false;
        }
    };

    let mut stream = match TcpStream::connect(&addr) {
        Ok(s) => s,
        Err(e) => {
            info!("Error: {e}");
            return false;
        }
    };

    // Perform pairing
    let result = pair_with_camera(
        &mut stream,
        clients.client_motion.key_packages(),
        clients.client_livestream.key_packages(),
        clients.client_fcm.key_packages(),
        clients.client_config.key_packages(),
        camera_secret,
    );

    let (
        camera_motion_key_packages,
        camera_motion_welcome_msg,
        camera_livestream_key_packages,
        camera_livestream_welcome_msg,
        camera_fcm_key_packages,
        camera_fcm_welcome_msg,
        camera_config_key_packages,
        camera_config_welcome_msg,
    ) = match result {
        Ok(r) => r,
        Err(e) => {
            info!("Error: {e}");
            return false;
        }
    };
    // Motion
    let motion_contact = clients
        .client_motion
        .add_contact(&camera_name, camera_motion_key_packages)
        .unwrap();

    if let Err(e) = process_welcome_message(
        &mut clients.client_motion,
        motion_contact,
        camera_motion_welcome_msg,
    ) {
        info!("Error: {e}");
        return false;
    }

    // Livestream
    let livestream_contact = clients
        .client_livestream
        .add_contact(&camera_name, camera_livestream_key_packages)
        .unwrap();

    if let Err(e) = process_welcome_message(
        &mut clients.client_livestream,
        livestream_contact,
        camera_livestream_welcome_msg,
    ) {
        info!("Error: {e}");
        return false;
    }

    // FCM
    let fcm_contact = clients
        .client_fcm
        .add_contact(&camera_name, camera_fcm_key_packages)
        .unwrap();

    if let Err(e) =
        process_welcome_message(&mut clients.client_fcm, fcm_contact, camera_fcm_welcome_msg)
    {
        info!("Error: {e}");
        return false;
    }

    // Config
    let config_contact = clients
        .client_config
        .add_contact(&camera_name, camera_config_key_packages)
        .unwrap();

    if let Err(e) = process_welcome_message(
        &mut clients.client_config,
        config_contact,
        camera_config_welcome_msg,
    ) {
        info!("Error: {e}");
        return false;
    }

    // Send Wi-Fi info
    if standalone_camera {
        let group_name = clients
            .client_config
            .get_group_name(&camera_name)
            .unwrap();
        if let Err(e) = send_wifi_info(
            &mut stream,
            &mut clients.client_config,
            group_name,
            wifi_ssid,
            wifi_password,
        ) {
            info!("Error: {e}");
            return false;
        }
    }

    true
}

//good
pub fn initialize(
    clients: &mut Option<Box<Clients>>,
    file_dir: String,
    first_time: bool,
) -> io::Result<bool> {
    info!("Initialize start");
    *clients = None;

    info!("Before get_app_names");
    let app_motion_name = get_app_name(first_time, file_dir.clone(), "app_motion_name".to_string());
    let app_livestream_name = get_app_name(
        first_time,
        file_dir.clone(),
        "app_livestream_name".to_string(),
    );
    let app_fcm_name = get_app_name(first_time, file_dir.clone(), "app_fcm_name".to_string());
    let app_config_name = get_app_name(first_time, file_dir.clone(), "app_config_name".to_string());

    info!("Before Clients::new");

    *clients = Some(Box::new(Clients::new(
        app_motion_name,
        app_livestream_name,
        app_fcm_name,
        app_config_name,
        first_time,
        file_dir,
    )?));

    Ok(true)
}

fn read_next_msg_from_file(file: &mut File) -> io::Result<Vec<u8>> {
    let mut len_buffer = [0u8; 4];
    let len_bytes_read = file.read(&mut len_buffer)?;
    if len_bytes_read != 4 {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: not enough bytes to read the len from file"),
        ));
    }

    let msg_len = u32::from_be_bytes(len_buffer);

    let mut buffer = vec![0; msg_len.try_into().unwrap()];
    let bytes_read = file.read(&mut buffer)?;
    if bytes_read != msg_len as usize {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: not enough bytes to read the message from file"),
        ));
    }

    Ok(buffer)
}

pub fn decrypt_video(
    clients: &mut Option<Box<Clients>>,
    encrypted_filename: String,
) -> io::Result<String> {
    if clients.is_none() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: clients not initialized!"),
        ));
    }

    let file_dir = clients.as_mut().unwrap().client_motion.get_file_dir();
    info!("File dir: {}", file_dir);
    let enc_pathname: String = encrypted_filename;

    let mut enc_file = fs::File::open(enc_pathname).expect("Could not open encrypted file");

    let enc_msg = read_next_msg_from_file(&mut enc_file)?;
    // The first message is a commit message
    clients
        .as_mut()
        .unwrap()
        .client_motion
        .decrypt(enc_msg, false)?;

    let enc_msg = read_next_msg_from_file(&mut enc_file)?;
    // The second message is the video info
    let dec_msg = clients
        .as_mut()
        .unwrap()
        .client_motion
        .decrypt(enc_msg, true)?;

    let info: VideoNetInfo = bincode::deserialize(&dec_msg)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;

    if info.sanity != *VIDEONETINFO_SANITY || info.num_msg == 0 {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            "Error: Corrupt VideoNetInfo message.",
        ));
    }

    // The rest of the messages are video data
    //Note: we're building the filename based on the timestamp in the message.
    //The encrypted filename however is not protected and hence the server could have changed it.
    //Therefore, it is possible that the names won't match.
    //This is not an issue.
    //We should use the timestamp in the decrypted filename going forward
    //and discard the encrypted filename.
    let dec_filename = format!("video_{}.mp4", info.timestamp);
    let dec_pathname: String = file_dir.to_owned() + "/" + &dec_filename;

    let mut dec_file = fs::File::create(&dec_pathname).expect("Could not create decrypted file");

    for expected_chunk_number in 0..info.num_msg {
        let enc_msg = read_next_msg_from_file(&mut enc_file)?;
        let dec_msg = clients
            .as_mut()
            .unwrap()
            .client_motion
            .decrypt(enc_msg, true)?;

        // check the chunk number
        if dec_msg.len() < 8 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("Error: too few bytes!"),
            ));
        }

        let chunk_number = u64::from_be_bytes(dec_msg[..8].try_into().unwrap());
        if chunk_number != expected_chunk_number {
            // Need to save groups state since we might have committed an update.
            clients.as_mut().unwrap().client_motion.save_groups_state();
            let _ = fs::remove_file(&dec_pathname);
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("Error: invalid chunk number!"),
            ));
        }

        let _ = dec_file.write_all(&dec_msg[8..]);
    }

    // Here, we first make sure the dec_file is flushed.
    // Then, we save groups state, which persists the update.
    dec_file.flush().unwrap();
    dec_file.sync_all().unwrap();
    clients.as_mut().unwrap().client_motion.save_groups_state();

    Ok(dec_filename)
}

pub fn decrypt_fcm_message(
    clients: &mut Option<Box<Clients>>,
    message: Vec<u8>,
) -> io::Result<String> {
    if clients.is_none() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: clients not initialized!"),
        ));
    }

    let dec_msg_bytes = clients
        .as_mut()
        .unwrap()
        .client_fcm
        .decrypt(message, true)?;
    clients.as_mut().unwrap().client_fcm.save_groups_state();

    // New JSON structure. Ensure valid JSON string
    if let Ok(message) = str::from_utf8(&dec_msg_bytes) {
        if serde_json::from_str::<serde_json::Value>(message).is_ok() {
            return Ok(message.to_string());
        }
    }

    let response = if dec_msg_bytes.len() == 8 {
        let timestamp: u64 = bincode::deserialize(&dec_msg_bytes)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;
        if timestamp != 0 {
            timestamp.to_string()
        } else {
            "Download".to_string()
        }
    } else {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!(
                "Error: invalid len in decrypted msg ({})",
                dec_msg_bytes.len()
            ),
        ));
    };

    Ok(response)
}

pub fn get_motion_group_name(
    clients: &mut Option<Box<Clients>>,
    camera_name: String,
) -> io::Result<String> {
    if clients.is_none() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: clients not initialized!"),
        ));
    }

    clients
        .as_mut()
        .unwrap()
        .client_motion
        .get_group_name(&camera_name)
}

pub fn get_livestream_group_name(
    clients: &mut Option<Box<Clients>>,
    camera_name: String,
) -> io::Result<String> {
    if clients.is_none() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: clients not initialized!"),
        ));
    }

    clients
        .as_mut()
        .unwrap()
        .client_livestream
        .get_group_name(&camera_name)
}

pub fn livestream_decrypt(
    clients: &mut Option<Box<Clients>>,
    enc_data: Vec<u8>,
    expected_chunk_number: u64,
) -> io::Result<Vec<u8>> {
    if clients.is_none() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: clients not initialized!"),
        ));
    }

    let dec_data = clients
        .as_mut()
        .unwrap()
        .client_livestream
        .decrypt(enc_data, true)?;
    clients
        .as_mut()
        .unwrap()
        .client_livestream
        .save_groups_state();

    // check the chunk number
    if dec_data.len() < 8 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("Error: too few bytes!"),
        ));
    }

    let chunk_number = u64::from_be_bytes(dec_data[..8].try_into().unwrap());
    if chunk_number != expected_chunk_number {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("Error: invalid chunk number!"),
        ));
    }

    Ok(dec_data[8..].to_vec())
}

pub fn livestream_update(
    clients: &mut Option<Box<Clients>>,
    updates_msg: Vec<u8>,
) -> io::Result<()> {
    if clients.is_none() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("Error: clients not initialized!"),
        ));
    }

    let update_commit_msgs: Vec<Vec<u8>> = bincode::deserialize(&updates_msg)
        .map_err(|e| {
            io::Error::new(
                io::ErrorKind::Other,
                format!("Error: deserialization of updates_msg failed! - {e}"),
            )
        })?;

    for commit_msg in update_commit_msgs {
        let _ = clients
            .as_mut()
            .unwrap()
            .client_livestream
            .decrypt(commit_msg, false)?;
    }

    clients
        .as_mut()
        .unwrap()
        .client_livestream
        .save_groups_state();

    Ok(())
}

pub fn deregister(clients: &mut Option<Box<Clients>>) {
    if clients.is_none() {
        info!("Error: clients not initialized!");
        return;
    }

    match clients.as_mut().unwrap().client_motion.clean() {
        Ok(_) => {}
        Err(e) => {
            info!("Error: Deregistering client_motion failed: {e}");
        }
    }

    match clients.as_mut().unwrap().client_livestream.clean() {
        Ok(_) => {}
        Err(e) => {
            info!("Error: Deregistering client_livestream failed: {e}")
        }
    }

    match clients.as_mut().unwrap().client_fcm.clean() {
        Ok(_) => {}
        Err(e) => {
            info!("Error: Deregistering client_fcm failed: {e}")
        }
    }

    match clients.as_mut().unwrap().client_config.clean() {
        Ok(_) => {}
        Err(e) => {
            info!("Error: Deregistering client_config failed: {e}")
        }
    }

    // FIXME: We currently support one camera only. Therefore, here, we delete all state files.
    // let _ = fs::remove_file(file_dir.clone() + "/app_motion_name");
    //let _ = fs::remove_file(file_dir.clone() + "/app_livestream_name");
    //let _ = fs::remove_file(file_dir.clone() + "/app_fcm_name");
    //let _ = fs::remove_file(file_dir.clone() + "/app_config_name");


    *clients = None;
}
