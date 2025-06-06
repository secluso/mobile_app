class Constants {
  static const proprietaryCameraIp = "10.42.0.1";
  static const cameraWaitingLock =
      "camera_waiting_lock.lock"; // A lock on the queues containing information about cameras waiting to be downloaded
  static const genericDownloadTaskLock =
      "generic_download_task.lock"; // A lock on the methods that start processing downloads (individual for foreground, bulk download in background...)
  static const numCameraSecretBytes =
      72; // The number of bytes within a camera secret
  static const credentialsLength =
      28; // The number of bytes within a user credentials QR code
  static const usernameLength =
      14; // The number of bytes within a user credentials QR code that belong to the user [first X bytes]
  static const passwordLength =
      14; // The number of bytes within a user credentials QR code that belong to the password [username bytes, username bytes + X]
  static const downloadBatchSize =
      2; // The number of cameras to simultaneously download from
}

// Types to be used for groups in Rust
class Group {
  static const motion = "motion";
  static const config = "config";
  static const livestream = "livestream";
}
