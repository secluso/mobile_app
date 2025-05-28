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

  static const proprietaryCameraIp = "10.42.0.1";
  static const numCameraSecretBytes =
      72; // The number of bytes within a camera secret
  static const credentialsLength =
      28; // The number of bytes within a user credentials QR code
  static const usernameLength =
      14; // The number of bytes within a user credentials QR code that belong to the user [first X bytes]
  static const passwordLength =
      14; // The number of bytes within a user credentials QR code that belong to the password [username bytes, username bytes + X]
}
