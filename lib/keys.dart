//! SPDX-License-Identifier: GPL-3.0-or-later

class PrefKeys {
  static const needUpdateFcmToken = 'need_update_fcm_token';
  static const needUpdateIosRelayBinding = 'need_update_ios_relay_binding';
  static const needUploadIosNotificationTarget =
      'need_upload_ios_notification_target';
  static const cameraSet = 'camera_set';
  static const needNotification = 'saved_need_notification_state';
  static const fcmToken = 'fcm_token';
  static const fcmConfigJson = 'fcm_config_json';
  static const iosApnsToken = 'ios_apns_token';
  static const iosAppInstallId = 'ios_app_install_id';
  static const iosAppAttestKeyId = 'ios_app_attest_key_id';
  static const iosRelayAttested = 'ios_relay_attested';
  static const iosRelayAttestedKeyId = 'ios_relay_attested_key_id';
  static const iosRelayHubToken = 'ios_relay_hub_token';
  static const iosRelayHubTokenExpiryMs = 'ios_relay_hub_token_expiry_ms';
  static const iosRelayBindingJson = 'ios_relay_binding_json';
  static const serverAddr = "server_addr";
  static const serverUsername = "server_username";
  static const serverPassword = "server_password";
  static const recordingMotionVideosPrefix = "recording_motion_videos_";
  static const lastRecordingTimestampPrefix = "last_recording_timestamp_";
  static const cameraNameKey = "camera_name_key";
  static const lastCameraAdd = "last_camera_add";
  static const downloadCameraQueue = "download_camera_queue";
  static const backupDownloadCameraQueue = "backup_download_camera_queue";
  static const downloadActiveCameras = "download_active_cameras";
  static const notificationsEnabled = "notifications_enabled";
  static const lastNotificationCheck = "last_notification_check";
  static const storageAutoCleanupEnabled = "storage_auto_cleanup_enabled";
  static const storageRetentionDays = "storage_retention_days";
  static const storageLastCleanupMs = "storage_last_cleanup_ms";
  static const numIgnoredHeartbeatsPrefix = "num_ignored_heartbeat_";
  static const cameraStatusPrefix = "camera_status_";
  static const numHeartbeatNotificationsPrefix = "num_heartbeat_notifications_";
  static const lastHeartbeatTimestampPrefix = "last_heartbeat_timestamp_";
  static const firmwareVersionPrefix = "firmware_version_";
  static const lastOutdatedNotification = "last_outdated_notification";
}
