import 'dart:io' show Platform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:privastead_flutter/notifications/download_task.dart';
import 'package:workmanager/workmanager.dart';

const String _bgTaskId = 'com.privastead.task'; // Matches Info.plist
const String _workerName = 'download_worker'; // free-form tag
const int _maxRetries = 5;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskId, inputData) async {
    print("Running task in background");
    final camera = inputData?['camera'] as String? ?? 'Unknown';
    final retry = inputData?['retry'] as int? ?? 0;

    if (camera != 'Unknown') {
      final ok = await doWork(camera);

      if (!ok && retry < _maxRetries) {
        print("Retrying due to failure (and < than max retries)");
        final nextRetry = retry + 1;
        final delayMin = nextRetry * nextRetry * 15;

        await Workmanager().registerOneOffTask(
          _bgTaskId,
          _workerName,
          inputData: {'camera': camera, 'retry': nextRetry},
          existingWorkPolicy: ExistingWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.connected),
          initialDelay:
              Platform.isIOS ? Duration(minutes: delayMin) : Duration.zero,
        );
      }

      return ok; // Intreprets true=success, false=retry
    } else {
      print(
        'TODO: Incorporate special startup behavior to fetch all cameras in crash scenario.',
      );
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

    print("DownloadScheduler: Initializing");

    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: debug && Platform.isAndroid,
    ); // debug mode only on android

    // Send one BG task so force-quit users recover on next launch
    // IMPORTANT TODO: We need to feed a camera name, or this will always fail. Should we loop through all cameras, as this is only at startup? Should we make then a special option?
    await Workmanager().registerOneOffTask(
      _bgTaskId,
      _workerName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      initialDelay:
          Platform.isIOS ? const Duration(minutes: 15) : Duration.zero,
    );
  }

  //TODO: Say that we put our scheduled task 15 minutes in the future. What happens if we somehow complete it before then? What if, another notif comes through, but we can't read it yet since we haven't decoded this one...
  /// Attempts now, else queues BG task.
  static Future<void> scheduleVideoDownload(String camera) async {
    print("Scheduling video download for $camera");
    // Try right now if network policy allows
    final List<ConnectivityResult> connectivityResult =
        await (Connectivity().checkConnectivity());
    final wifi = connectivityResult.contains(ConnectivityResult.wifi);
    final cell = connectivityResult.contains(ConnectivityResult.mobile);
    final allowCellular = true; // TODO: load from settings

    print("Network statuses: wifi = $wifi, cell = $cell");
    // TODO: We can't do work now in Android due to the ObjectBox error where we can't double instantiate (as Android background work doesn't hold the lock that the main process does, so it can't touch the database)
    if (Platform.isIOS && (wifi || (cell && allowCellular))) {
      print("Trying to do work now for $camera");
      final ok = await doWork(camera);
      if (ok) return; // Success in foreground
      // Else, fall through to queue
    }

    print("Continuing to queue one 15 min task for $camera");

    // Enqueue ONE BG task (15-min rule on iOS)
    await Workmanager().cancelByUniqueName(_bgTaskId); // ensure none pending
    // TODO: What happens if we have multiple cameras? Given we have the same background task ID for all, we might end up cancelling video download for an important camera
    // TODO: We should probably adopt use only one task (for IOS anyway), but manage a pending queue in SharedPreferences or ObjectBox
    await Workmanager().registerOneOffTask(
      _bgTaskId,
      _workerName,
      inputData: {'camera': camera, 'retry': 0},
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      initialDelay:
          Platform.isIOS ? const Duration(minutes: 15) : Duration.zero,
    );
  }
}
