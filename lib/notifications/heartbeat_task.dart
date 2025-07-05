import 'package:privastead_flutter/constants.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/notifications/notifications.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:privastead_flutter/src/rust/frb_generated.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class RustBridgeHelper {
  static bool _initialized = false;

  static Future<void>? _initFuture;

  /// Call this to avoid double-initialize in Android in the entry-point
  static Future<void> ensureInitialized() {
    if (_initialized) {
      return Future.value();
    }

    _initFuture ??= _doInit();
    return _initFuture!;
  }

  static Future<void> _doInit() async {
    await RustLib.init();
    _initialized = true;
  }
}

Future<bool> doHeartbeatTask(String cameraName) async {
  if (Platform.isAndroid) {
    await RustBridgeHelper.ensureInitialized();
  }
  Log.d("Starting to work (heartbeat)");
  
  //FIXME: don't attempt a heartbeat if we're livestreaming.

  final prefs = await SharedPreferences.getInstance();
  final timestampInt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final timestamp = BigInt.from(timestampInt);
  Log.d("Heartbeat timestamp = $timestamp");

  var lastHeartbeatTimestamp = prefs.getInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName) ?? 0;
  if (timestampInt - lastHeartbeatTimestamp < 60) {
    Log.d("Dropping this heartbeat task since we recently executed one.");
    return false;
  }
  await prefs.setInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName, timestampInt);

  final encConfigMsg = await generateHeartbeatRequestConfigCommand(
    cameraName: cameraName,
    timestamp: timestamp,
  );

  final res = await HttpClientService.instance.configCommand(
    cameraName: cameraName,
    command: encConfigMsg,
  );

  await res.fold(
    (_) async {
      await Future.delayed(Duration(seconds: 5));
      final fetchRes = await HttpClientService.instance.fetchConfigResponse(cameraName: "office");
      await fetchRes.fold(
        (configResponse) async {
          final heartbeatResult = await processHeartbeatConfigResponse(
            cameraName: cameraName,
            configResponse: configResponse,
            expectedTimestamp: timestamp,
          );
          Log.d("heartbeatResult = $heartbeatResult");
          if (heartbeatResult == "healthy") {
            Log.d("Processing healthy heartbeat");
            await prefs.setInt(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName, 0);
            await prefs.setInt(PrefKeys.cameraStatusPrefix + cameraName, CameraStatus.online);
            await prefs.setInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName, 0);
          } else if (heartbeatResult == "invalid ciphertext") {
            Log.d("Processing invalid ciphertext heartbeat");
            await prefs.setInt(PrefKeys.cameraStatusPrefix + cameraName, CameraStatus.corrupted);
            var numHeartbeatNotifications = prefs.getInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName) ?? 0;
            // It could be annoying if we keep showing these notifications.
            if (numHeartbeatNotifications < 2) {
              showHeartbeatNotification(
                cameraName: cameraName,
                msg: "Camera connection is corrupted. Pair again.",
              );
              await prefs.setInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName, numHeartbeatNotifications + 1);
            }
          } else { //invalid timestamp || invalid epoch || Error
            // Note on "invalid epoch": Ideally, we want to be able to move this case to the previous else if block (i.e, invalid ciphertext).
            // That is, we want "invalid epoch" to clearly show an MLS channel corruption.
            // However, currently, "invalid epoch" could also happen if there's a race between a heartbeat
            // and motion video trigger on the camera (or even a livestream start on the app).
            // If we can prevent these races, then we can then be sure that "invalid epoch" means corruption.
            // To prevent a race with motion, it should be enough to make sure we download and process any pending motion
            // videos in the server before processing the heartbeat response.
            // To prevent a race with livestream, we should disallow livestreaming while we're working on a heartbeat.
            var numIgnoredHeartbeats = prefs.getInt(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName) ?? 0;
            numIgnoredHeartbeats++;
            await prefs.setInt(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName, numIgnoredHeartbeats);
            Log.d("number of consecutive ignored heartbeats = $numIgnoredHeartbeats");
            if (numIgnoredHeartbeats >= 2) {
              await prefs.setInt(PrefKeys.cameraStatusPrefix + cameraName, CameraStatus.possiblyCorrupted);
              var numHeartbeatNotifications = prefs.getInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName) ?? 0;
              if (numHeartbeatNotifications < 2) {
                showHeartbeatNotification(
                  cameraName: cameraName,
                  msg: "Camera connection is likely corrupted. Pair again.",
                );
                await prefs.setInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName, numHeartbeatNotifications + 1);
              }
            }
          }
        },
        (err) async {
          Log.d('Error fetching heartbeat config response: $err');
          await prefs.setInt(PrefKeys.cameraStatusPrefix + cameraName, CameraStatus.offline);
          var numHeartbeatNotifications = prefs.getInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName) ?? 0;
          if (numHeartbeatNotifications < 2) {
            showHeartbeatNotification(
              cameraName: cameraName,
              msg: "Camera seems to be offline.",
            );
          }
          return false;
        },
      );
    },
    (err) async {
      Log.d('Error sending heartbeat config command: $err');
      return false;
    },
  );

  return false;
}