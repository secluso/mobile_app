import 'package:privastead_flutter/constants.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/notifications/download_task.dart';
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

/// Splits [input] into two parts: before and after the first underscore.
/// If there's no underscore, returns (input, "").
List<String> splitAtUnderscore(String input) {
  final index = input.indexOf('_');
  if (index == -1) {
    return [input, ""];
  }
  final before = input.substring(0, index);
  final after = input.substring(index + 1);
  return [before, after];
}

Future<bool> _doHeartbeatTask(String cameraName) async {
  Log.d("$cameraName: Starting to work (heartbeat)");

  //FIXME: don't attempt a heartbeat if we're livestreaming.

  final prefs = await SharedPreferences.getInstance();
  final timestampInt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final timestamp = BigInt.from(timestampInt);
  var successful = false;
  Log.d("$cameraName: Heartbeat timestamp = $timestamp");

  var lastHeartbeatTimestamp =
      prefs.getInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName) ?? 0;
  if (timestampInt - lastHeartbeatTimestamp < 60) {
    Log.d(
      "$cameraName: Dropping this heartbeat task since we recently executed one.",
    );
    return false;
  }
  await prefs.setInt(
    PrefKeys.lastHeartbeatTimestampPrefix + cameraName,
    timestampInt,
  );

  final encConfigMsg = await generateHeartbeatRequestConfigCommand(
    cameraName: cameraName,
    timestamp: timestamp,
  );

  final res = await HttpClientService.instance.configCommand(
    cameraName: cameraName,
    command: encConfigMsg,
  );

  // Download pending videos before processing the heartbeat response.
  // This prevents thinking that the MLS channel is corrupted if there
  // are pending video files in the server.
  await retrieveVideos(cameraName);

  await res.fold(
    (_) async {
      for (int i = 0; i < 30 && !successful; i++) {
        await Future.delayed(Duration(seconds: 2));
        final fetchRes = await HttpClientService.instance.fetchConfigResponse(
          cameraName: cameraName,
        );
        await fetchRes.fold(
          (configResponse) async {
            final heartbeatResult = await processHeartbeatConfigResponse(
              cameraName: cameraName,
              configResponse: configResponse,
              expectedTimestamp: timestamp,
            );
            Log.d("$cameraName: heartbeatResult = $heartbeatResult");
            final heartbeatResultParts = splitAtUnderscore(heartbeatResult);

            if (heartbeatResultParts[0] == "healthy") {
              Log.d("$cameraName: Processing healthy heartbeat");
              await prefs.setInt(
                PrefKeys.numIgnoredHeartbeatsPrefix + cameraName,
                0,
              );
              var previousCameraStatus =
                  prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
                  CameraStatus.online;
              await prefs.setInt(
                PrefKeys.cameraStatusPrefix + cameraName,
                CameraStatus.online,
              );
              await prefs.setInt(
                PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                0,
              );
              final firmwareVersion = heartbeatResultParts[1];
              if (firmwareVersion != "") {
                final currentFirmware =
                    prefs.getString(
                      PrefKeys.firmwareVersionPrefix + cameraName,
                    ) ??
                    "";
                if (currentFirmware != firmwareVersion) {
                  showCameraStatusNotification(
                    cameraName: cameraName,
                    msg:
                        "Camera's Privastead firmware version has been updated to $firmwareVersion.",
                  );
                }
                await prefs.setString(
                  PrefKeys.firmwareVersionPrefix + cameraName,
                  heartbeatResultParts[1],
                );
              }
              var sendNotificationGlobal =
                  prefs.getBool(PrefKeys.notificationsEnabled) ?? true;

              if (previousCameraStatus != CameraStatus.online &&
                  sendNotificationGlobal) {
                Log.d("Showing notification: Camera connection is restored.");
                showCameraStatusNotification(
                  cameraName: cameraName,
                  msg: "Camera connection is restored.",
                );
              }
            } else if (heartbeatResultParts[0] == "invalid ciphertext") {
              Log.d("$cameraName: Processing invalid ciphertext heartbeat");
              await prefs.setInt(
                PrefKeys.cameraStatusPrefix + cameraName,
                CameraStatus.corrupted,
              );
              var numHeartbeatNotifications =
                  prefs.getInt(
                    PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                  ) ??
                  0;
              var sendNotificationGlobal =
                  prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
              // It could be annoying if we keep showing these notifications.
              if (numHeartbeatNotifications < 2 && sendNotificationGlobal) {
                Log.d("Showing notification: Camera connection is corrupted.");
                showCameraStatusNotification(
                  cameraName: cameraName,
                  msg: "Camera connection is corrupted. Pair again.",
                );
                await prefs.setInt(
                  PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                  numHeartbeatNotifications + 1,
                );
              }
            } else {
              //invalid timestamp || invalid epoch || Error
              // Note on "invalid epoch": Ideally, we want to be able to move this case to the previous else if block (i.e, invalid ciphertext).
              // That is, we want "invalid epoch" to clearly show an MLS channel corruption.
              // However, "invalid epoch" could also happen if there's a race between a heartbeat
              // and motion video trigger on the camera (or even a livestream start on the app).
              // We've tried to prevent that for motion videos by downloading and processing any pending motion
              // videos in the server before processing the heartbeat response.
              // To prevent a race with livestream, we should disallow livestreaming while we're working on a heartbeat.
              var numIgnoredHeartbeats =
                  prefs.getInt(
                    PrefKeys.numIgnoredHeartbeatsPrefix + cameraName,
                  ) ??
                  0;
              numIgnoredHeartbeats++;
              await prefs.setInt(
                PrefKeys.numIgnoredHeartbeatsPrefix + cameraName,
                numIgnoredHeartbeats,
              );
              Log.d(
                "$cameraName: number of consecutive ignored heartbeats = $numIgnoredHeartbeats",
              );
              if (numIgnoredHeartbeats >= 2) {
                await prefs.setInt(
                  PrefKeys.cameraStatusPrefix + cameraName,
                  CameraStatus.possiblyCorrupted,
                );
                var numHeartbeatNotifications =
                    prefs.getInt(
                      PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                    ) ??
                    0;
                var sendNotificationGlobal =
                    prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
                if (numHeartbeatNotifications < 2 && sendNotificationGlobal) {
                  Log.d(
                    "Showing notification: Camera connection is likely corrupted.",
                  );
                  showCameraStatusNotification(
                    cameraName: cameraName,
                    msg: "Camera connection is likely corrupted. Pair again.",
                  );
                  await prefs.setInt(
                    PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
                    numHeartbeatNotifications + 1,
                  );
                }
              }
            }

            successful = true;
          },
          (err) async {
            Log.d(
              '$cameraName: Error fetching heartbeat config response (attempt $i): $err',
            );
          },
        );
      }

      if (!successful) {
        // We get here if we could not successfully fetch the response in all the attempts in the loop
        // If we delete the camera while heartbeat is taking place, we could end up
        // here after the camera is deleted. So we check that here.
        final existingSet =
            prefs.getStringList(PrefKeys.cameraSet) ?? <String>[];
        if (existingSet.contains(cameraName)) {
          Log.d(
            '$cameraName: Error fetching heartbeat config response in all attempts.',
          );
          await prefs.setInt(
            PrefKeys.cameraStatusPrefix + cameraName,
            CameraStatus.offline,
          );
          var numHeartbeatNotifications =
              prefs.getInt(
                PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
              ) ??
              0;
          var sendNotificationGlobal =
              prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
          if (numHeartbeatNotifications < 2 && sendNotificationGlobal) {
            Log.d("Showing notification: Camera is offline.");
            showCameraStatusNotification(
              cameraName: cameraName,
              msg: "Camera seems to be offline.",
            );
            await prefs.setInt(
              PrefKeys.numHeartbeatNotificationsPrefix + cameraName,
              numHeartbeatNotifications + 1,
            );
          }
        }
      }
    },
    (err) async {
      Log.d('$cameraName: Error sending heartbeat config command: $err');
    },
  );

  return successful;
}

Future<void> updateCameraStatusFcmNotification(
  String fcmTimestampString,
  String cameraName,
) async {
  final prefs = await SharedPreferences.getInstance();
  var cameraStatus =
      prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
      CameraStatus.online;
  Log.d("updateCameraStatusFcmNotification: camera status = $cameraStatus");

  if (cameraStatus == CameraStatus.offline) {
    final lastHeartbeatTimestamp =
        prefs.getInt(PrefKeys.lastHeartbeatTimestampPrefix + cameraName) ?? 0;
    final fcmTimestamp = int.tryParse(fcmTimestampString);

    if (lastHeartbeatTimestamp != 0 && fcmTimestamp! > lastHeartbeatTimestamp) {
      await prefs.setInt(
        PrefKeys.cameraStatusPrefix + cameraName,
        CameraStatus.online,
      );
      var sendNotificationGlobal =
          prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
      if (sendNotificationGlobal) {
        Log.d("Showing notification: Camera connection is restored.");
        showCameraStatusNotification(
          cameraName: cameraName,
          msg: "Camera connection is restored.",
        );
      }
    }
  }
}

Future<void> updateCameraStatusLivestream(String cameraName) async {
  final prefs = await SharedPreferences.getInstance();
  var cameraStatus =
      prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
      CameraStatus.online;
  Log.d("updateCameraStatusLivestream: camera status = $cameraStatus");

  if (cameraStatus == CameraStatus.offline) {
    await prefs.setInt(
      PrefKeys.cameraStatusPrefix + cameraName,
      CameraStatus.online,
    );
    var sendNotificationGlobal =
        prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
    if (sendNotificationGlobal) {
      Log.d("Showing notification: Camera connection is restored.");
      showCameraStatusNotification(
        cameraName: cameraName,
        msg: "Camera connection is restored.",
      );
    }
  }
}

Future<void> doAllHeartbeatTasks(bool inBackground) async {
  if (Platform.isAndroid && inBackground) {
    await RustBridgeHelper.ensureInitialized();
  }
  Log.d("Starting to run all heartbeat tasks");

  final prefs = await SharedPreferences.getInstance();
  final List<String> cameraSet = prefs.getStringList(PrefKeys.cameraSet) ?? [];

  for (final cameraName in cameraSet) {
    await _doHeartbeatTask(cameraName);
  }
}
