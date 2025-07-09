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
  Log.d("$cameraName: Starting to work (heartbeat)");
  
  //FIXME: don't attempt a heartbeat if we're livestreaming.

  final prefs = await SharedPreferences.getInstance();
  final timestampInt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final timestamp = BigInt.from(timestampInt);
  var successful = false;
  Log.d("$cameraName: Heartbeat timestamp = $timestamp");

  var lastHeartbeatTimestamp = prefs.getInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName) ?? 0;
  if (timestampInt - lastHeartbeatTimestamp < 60) {
    Log.d("$cameraName: Dropping this heartbeat task since we recently executed one.");
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
      
      for (int i = 0; i < 10 && !successful; i++) {
        await Future.delayed(Duration(seconds: 2));
        final fetchRes = await HttpClientService.instance.fetchConfigResponse(cameraName: cameraName);
        await fetchRes.fold(
          (configResponse) async {
            final heartbeatResult = await processHeartbeatConfigResponse(
              cameraName: cameraName,
              configResponse: configResponse,
              expectedTimestamp: timestamp,
            );
            Log.d("$cameraName: heartbeatResult = $heartbeatResult");
            if (heartbeatResult == "healthy") {
              Log.d("$cameraName: Processing healthy heartbeat");
              await prefs.setInt(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName, 0);
              await prefs.setInt(PrefKeys.cameraStatusPrefix + cameraName, CameraStatus.online);
              await prefs.setInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName, 0);
            } else if (heartbeatResult == "invalid ciphertext") {
              Log.d("$cameraName: Processing invalid ciphertext heartbeat");
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
              Log.d("$cameraName: number of consecutive ignored heartbeats = $numIgnoredHeartbeats");
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

            successful = true;
          },
          (err) async {
            Log.d('$cameraName: Error fetching heartbeat config response (attempt $i): $err');
          },
        );
      }

      if (!successful) {
        // We get here if we could not successfully fetch the response in all the attempts in the loop
        Log.d('$cameraName: Error fetching heartbeat config response in all attempts.');
        await prefs.setInt(PrefKeys.cameraStatusPrefix + cameraName, CameraStatus.offline);
        var numHeartbeatNotifications = prefs.getInt(PrefKeys.numHeartbeatNotificationsPrefix + cameraName) ?? 0;
        if (numHeartbeatNotifications < 2) {
          showHeartbeatNotification(
            cameraName: cameraName,
            msg: "Camera seems to be offline.",
          );
        }
      }
    },
    (err) async {
      Log.d('$cameraName: Error sending heartbeat config command: $err');
    },
  );

  return successful;
}