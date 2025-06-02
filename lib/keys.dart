class PrefKeys {
  static const needUpdateFcmToken = 'need_update_fcm_token';
  static const cameraSet = 'camera_set';
  static const needNotification = 'saved_need_notification_state';
  static const fcmToken = 'fcm_token';
  static const savedIp = "server_ip";
  static const serverUsername = "server_username";
  static const serverPassword = "server_password";
  static const downloadingMotionVideos = "downloading_motion_videos";
  static const cameraNameKey = "camera_name_key";
  static const waitingAdditionalCamera = "waiting_additional_camera";
  static const waitingAdditionalCameraTime = "waiting_additional_camera_time";
  static const downloadCameraQueue = "download_camera_queue";
  static const backupDownloadCameraQueue = "backup_download_camera_queue";

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
