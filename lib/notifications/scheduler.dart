import 'dart:io' show Platform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/notifications/download_task.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'package:privastead_flutter/utilities/lock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String _bgTaskId = 'com.privastead.task'; // Matches Info.plist
const String _workerName = 'download_worker'; // free-form tag

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
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
        initialDelay:
            Platform.isIOS ? Duration(minutes: delayMin) : Duration.zero,
      );
      return ok; // Intreprets true=success, false=retry
    } else {
      // no new camera entries, everything succeeded... we can stop scheduling now
      return true;
    }
  });
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
      existingWorkPolicy: ExistingWorkPolicy.replace,
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
    if (Platform.isIOS && (wifi || (cell && allowCellular))) {
      Log.d("Trying to do work now for $camera");
      final ok = await doWorkNonBackground(camera);
      if (ok) return; // Success in foreground
      // Else, fall through to queue
    }

    Log.d("Continuing to queue one 15 min task for $camera");

    // Adds the camera to the waiting list if not already in there.
    if (await lock(PrefKeys.cameraWaitingLock)) {
      var sharedPref = await SharedPreferences.getInstance();
      if (sharedPref.containsKey(PrefKeys.downloadCameraQueue)) {
        var currentCameraList = sharedPref.getStringList(
          PrefKeys.downloadCameraQueue,
        );
        if (!currentCameraList!.contains(camera)) {
          currentCameraList.add(camera);
        }
      } else {
        sharedPref.setStringList(PrefKeys.downloadCameraQueue, [camera]);
      }

      await unlock(PrefKeys.cameraWaitingLock);
    } else {
      Log.e("Failed to acquire motion lock");
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
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
        initialDelay:
            Platform.isIOS ? const Duration(minutes: 15) : Duration.zero,
      );
    }
  }
}
