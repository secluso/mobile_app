//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show Platform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/download_task.dart';
import 'package:secluso_flutter/notifications/heartbeat_task.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String _bgTaskId = 'com.secluso.task'; // Matches Info.plist
const String _workerName = 'download_worker'; // free-form tag
const String _periodicTaskName = 'periodic_heartbeat_task';

class OneOffHelper {
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
    Log.init();
    _initialized = true;
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskId, inputData) async {
    if (Platform.isAndroid) {
      OneOffHelper.ensureInitialized();
    }

    Log.d("Executing task: $taskId");

    if (taskId == _workerName) {
      final retry = inputData?['retry'] as int? ?? 0;
      Log.d("Running task in background (iteration #$retry)");

      final ok = await doWorkBackground();

      if (!ok) {
        Log.d("Retrying due to failure / new entries");
        final nextRetry = retry + 1;
        final delayMin = nextRetry * nextRetry * 15;

        await Workmanager().registerOneOffTask(
          _bgTaskId,
          _workerName,
          inputData: {'retry': nextRetry},
          existingWorkPolicy: ExistingWorkPolicy.keep,
          constraints: Constraints(networkType: NetworkType.connected),
          initialDelay:
              Platform.isIOS ? Duration(minutes: delayMin) : Duration.zero,
        );
        return ok; // Intreprets true=success, false=retry
      } else {
        // no new camera entries, everything succeeded... we can stop scheduling now
        return true;
      }
    }

    if (taskId == _periodicTaskName) {
      Log.d("Running periodic heartbeat task for all cameras");
      await doAllHeartbeatTasks(true);
      return true;
    }

    return false;
  });
}

class HeartbeatScheduler {
  /// Initialization method
  static Future<void> registerPeriodicTask({bool debug = false}) async {
    Log.d("HeartbeatScheduler: Registering periodic tasks for all cameras.");

    // FIXME: we might be calling this multiple times, both here and in DownloadScheduler
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: debug && Platform.isAndroid,
    ); // debug mode only on android

    await Workmanager().registerPeriodicTask(
      'heartbeat',
      _periodicTaskName,
      frequency: Duration(hours: 6),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}

class DownloadScheduler {
  static bool _isInit = false;

  /// Initialization method
  static Future<void> init({bool debug = false}) async {
    if (_isInit) return;
    _isInit = true;

    Log.d("DownloadScheduler: Initializing");

    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: debug && Platform.isAndroid,
    ); // debug mode only on android

    // Send one BG task so force-quit users recover on next launch
    await Workmanager().registerOneOffTask(
      _bgTaskId,
      _workerName,
      inputData: {'retry': 0},
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
      initialDelay:
          Platform.isIOS ? const Duration(minutes: 15) : Duration.zero,
    );
  }

  /// Attempts now, else queues BG task.
  static Future<void> scheduleVideoDownload(String camera) async {
    Log.d("Scheduling video download for $camera");
    // Try right now if network policy allows
    final List<ConnectivityResult> connectivityResult =
        await (Connectivity().checkConnectivity());
    final wifi = connectivityResult.contains(ConnectivityResult.wifi);
    final cell = connectivityResult.contains(ConnectivityResult.mobile);
    final allowCellular = true; // TODO: load from settings

    Log.d("Network statuses: wifi = $wifi, cell = $cell");
    // TODO: We can't do work now in Android due to the ObjectBox error where we can't double instantiate (as Android background work doesn't hold the lock that the main process does, so it can't touch the database)
    if (!camera.isEmpty && (wifi || (cell && allowCellular))) {
      Log.d("Trying to do work now for $camera");
      final ok = await doWorkNonBackground(camera);
      if (ok) return; // Success in foreground
      // Else, fall through to queue
    }

    Log.d("Continuing to queue one 15 min task for $camera");

    // Adds the camera to the waiting list if not already in there.
    var lockSucceeded = await lock(Constants.cameraWaitingLock);
    if (!camera.isEmpty && lockSucceeded) {
      Log.d("Adding to queue for $camera");
      try {
        var sharedPref = SharedPreferencesAsync();
        if (await sharedPref.containsKey(PrefKeys.downloadCameraQueue)) {
          var currentCameraList = await sharedPref.getStringList(
            PrefKeys.downloadCameraQueue,
          );
          if (!currentCameraList!.contains(camera)) {
            Log.d("Added to pre-existing list for $camera");
            currentCameraList.add(camera);
            await sharedPref.setStringList(
              PrefKeys.downloadCameraQueue,
              currentCameraList,
            );
          } else {
            Log.d("List already contained $camera");
          }
        } else {
          Log.d("Created new string list for $camera");
          await sharedPref.setStringList(PrefKeys.downloadCameraQueue, [
            camera,
          ]);
        }
      } finally {
        // Ensure it's unlocked.
        await unlock(Constants.cameraWaitingLock);
      }
    } else {
      if (!lockSucceeded) Log.e("Failed to acquire motion lock");
    }

    // Enqueue ONE BG task (15-min rule on iOS)
    // It's not an issue if this doesn't run due to a currently running task. The currently running task will see a new camera added and queue another from itself.
    if (Platform.isIOS ||
        (Platform.isAndroid &&
            !await Workmanager().isScheduledByUniqueName(_bgTaskId))) {
      await Workmanager().cancelByUniqueName(_bgTaskId); // ensure none pending
      await Workmanager().registerOneOffTask(
        _bgTaskId,
        _workerName,
        inputData: {'retry': 0},
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
        initialDelay:
            Platform.isIOS
                ? const Duration(minutes: 15)
                : Duration
                    .zero, // TODO: Increase from zero potentially for Android. We may want a tiny delay to recieve info about any new cameras needing updates (especially at startup)
      );
    }
  }
}
