//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/src/rust/api.dart';
import 'package:secluso_flutter/routes/app_drawer.dart';
import 'package:secluso_flutter/src/rust/frb_generated.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/ui_state.dart';
import 'package:secluso_flutter/notifications/download_status.dart';
import 'package:secluso_flutter/notifications/epoch_markers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:ui';
import 'dart:isolate' hide IsolateNameServer;
import 'pending_processor.dart';

// We have another instance of this due to Android requiring another RustLib for our DownloadTasks. This isn't necessary for iOS. We can only have one instance per process, thus needing this.
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

const Duration _forceInitCooldown = Duration(seconds: 30);
const Duration _forceInitTimeout = Duration(seconds: 8);
final Map<String, DateTime> _forceInitLast = {};

bool _isEpochMismatch(String message) {
  return message.contains("message epoch") &&
      message.contains("group epoch");
}

Future<bool> _maybeForceInit(String cameraName, String reason) async {
  final now = DateTime.now();
  final lastAttempt = _forceInitLast[cameraName];
  if (lastAttempt != null && now.difference(lastAttempt) < _forceInitCooldown) {
    Log.w(
      "[download] Skipping force init for $cameraName (cooldown active, reason=$reason)",
    );
    return false;
  }

  _forceInitLast[cameraName] = now;
  Log.w("[download] Forcing init for $cameraName (reason=$reason)");
  return await initialize(cameraName, timeout: _forceInitTimeout, force: true);
}

Future<bool> doWorkNonBackground(String cameraName) async {
  // TODO: Should we wait for downloadingMotionVideos to be false before continuing? Is this meant to be a spinlock?

  if (await lock(Constants.genericDownloadTaskLock)) {
    try {
      Log.d("Starting to work in non-background mode");

      bool result = await retrieveVideos(cameraName);

      QueueProcessor.instance.signalNewFile();
      return result;
    } finally {
      await unlock(
        Constants.genericDownloadTaskLock,
      ); // Always ensure this unlocks, even on exceptions
    }
  } else {
    Log.w("Download task already running; will queue work");
    return false;
  }
}

Future<bool> doWorkBackground() async {
  // TODO: We should also create synchronization between any motion download (if we were to have some sort of download from the main)
  if (Platform.isAndroid) {
    await RustBridgeHelper.ensureInitialized();
  }
  Log.d("Starting to work");

  // Perform an initial check (before lock)
  var prefs = SharedPreferencesAsync();
  if (!await prefs.containsKey(PrefKeys.downloadCameraQueue) &&
      !await prefs.containsKey(PrefKeys.backupDownloadCameraQueue)) {
    Log.w("There are no pref keys to base off of.");
    return true;
  }

  if (await lock(Constants.genericDownloadTaskLock)) {
    try {
      var prefs = SharedPreferencesAsync();
      if (await lock(Constants.cameraWaitingLock)) {
        var downloadCameraQueue;
        try {
          // Secondary check after locking
          if (!await prefs.containsKey(PrefKeys.downloadCameraQueue) &&
              !await prefs.containsKey(PrefKeys.backupDownloadCameraQueue)) {
            Log.e("There are no pref keys to base off of.");
            return true;
          }

          downloadCameraQueue = await prefs.getStringList(
            PrefKeys.downloadCameraQueue,
          );

          var backupDownloadCameraQueue = await prefs.getStringList(
            PrefKeys.backupDownloadCameraQueue,
          );
          if (downloadCameraQueue == null) {
            downloadCameraQueue =
                backupDownloadCameraQueue; // Replace the existing queue with the pre-existing backup.
          } else if (backupDownloadCameraQueue != null) {
            // Merge the two queues (without duplicates by using sets)
            downloadCameraQueue =
                downloadCameraQueue
                    .toSet()
                    .union(backupDownloadCameraQueue.toSet())
                    .toList();
          }

          downloadCameraQueue = await _sanitizeDownloadQueue(
            downloadCameraQueue ?? <String>[],
          );
          if (downloadCameraQueue.isEmpty) {
            Log.w("No valid cameras in download queue after sanitization");
            await prefs.remove(PrefKeys.downloadCameraQueue);
            await prefs.remove(PrefKeys.backupDownloadCameraQueue);
            return true;
          }

          // Await these, so that they don't run outside the lock.
          await prefs.setStringList(
            PrefKeys.backupDownloadCameraQueue,
            downloadCameraQueue,
          ); // Create a backup of the current list.
          await prefs.remove(
            PrefKeys.downloadCameraQueue,
          ); // Delete the existing list, so that we know any new entries from this point will require an additional download later
        } finally {
          // Ensure this always unlocks
          await unlock(Constants.cameraWaitingLock);
          Log.d("Released lock");
        }
        if (downloadCameraQueue != null) {
          // What if we have uneven cameras within the batch? Say we have 6 cameras. Three have 10 videos to download. Three have 1. It seems best to associate them when batching, but we randomize currently.
          var batchSize = Constants.downloadBatchSize;
          var batchedQueue = batch(downloadCameraQueue, batchSize);
          Log.d("Batched Queue List: $batchedQueue");

          var retrieveResults = [];
          for (int i = 1; i <= batchedQueue.length; i++) {
            var currentSet = batchedQueue[i - 1];
            Log.d("Batch #$i = $currentSet");

            // Queue all of the current batch
            var currentFutures = [];
            for (int j = 0; j < currentSet.length; j++) {
              currentFutures.add(
                retrieveVideos(currentSet[j]),
              ); // This is an async function, so it'll run all of these in parallel
            }

            Log.d("Awaiting batch completion");
            // Wait for all of the current batch to complete.
            for (int j = 0; j < currentSet.length; j++) {
              retrieveResults.add(await currentFutures[j]);
            }
            Log.d("Batch completed");
          }

          // Track if at least one was successful, and if we had a single failure or not.
          var oneSuccessful = false;
          var allSuccessful = true;

          await lock(
            Constants.cameraWaitingLock,
          ); // TODO: I'm not sure what to do if this is false. Is it even possible for it to be false? It's blocking.

          try {
            var downloadQueueCopy = List<String>.from(downloadCameraQueue);
            for (int i = 0; i < batchedQueue.length; i++) {
              for (int j = 0; j < batchedQueue[i].length; j++) {
                var index = i * batchSize + j;
                if (retrieveResults[index]) {
                  oneSuccessful = true;
                  var cameraName =
                      downloadQueueCopy[index]; // Work from a clone to avoid self-modification
                  downloadCameraQueue.remove(cameraName);
                } else {
                  allSuccessful =
                      false; // We maintain a queue of ones that still need to be processed.
                }
              }
            }

            Log.d("After queue cleanup");

            // Merge the failed list and ones that still need updates.
            if (await prefs.containsKey(PrefKeys.downloadCameraQueue)) {
              Log.d("Merging lists together");
              List<String> updatedList =
                  (await prefs.getStringList(
                    PrefKeys.downloadCameraQueue,
                  ))!; // This cannot be null
              downloadCameraQueue =
                  downloadCameraQueue
                      .toSet()
                      .union(updatedList.toSet())
                      .toList();
            } else {
              Log.d("Prefs did not contain new updates");
            }

            // Set the new list to be scheduled next time,
            await prefs.setStringList(
              PrefKeys.downloadCameraQueue,
              downloadCameraQueue,
            );
            await prefs.remove(PrefKeys.backupDownloadCameraQueue);
          } finally {
            await unlock(
              Constants.cameraWaitingLock,
            ); // Always ensure this unlocks.
          }

          // If at least one succeeded, we know we need to potentially update the camera list.
          if (oneSuccessful) {
            Log.d("Signaling for camera list update");
            QueueProcessor.instance.signalNewFile();
          }

          // If some didn't succeed, we need to schedule another task to run later.
          // Additionally, there's a chance we could have more now from merging with the new list.
          // False means we retry the task again later
          var currentState = allSuccessful && downloadCameraQueue.length == 0;
          Log.d("Returning $currentState, all successful = $allSuccessful");
          return currentState;
        }
      } else {
        Log.w("Failed to acquire motion lock");
      }
    } finally {
      await unlock(
        Constants.genericDownloadTaskLock,
      ); // Always ensure this unlocks, even on exceptions
    }
  } else {
    Log.w("Download task already running; skipping background work");
    return true;
  }

  return false;
}

/// Separate a long list into batches of size batchSize
List<List<T>> batch<T>(List<T> items, int batchSize) {
  List<List<T>> result = [];
  for (var i = 0; i < items.length; i += batchSize) {
    result.add(
      items.sublist(
        i,
        i + batchSize > items.length ? items.length : i + batchSize,
      ),
    );
  }
  return result;
}

List<String> _dedupePreserveOrder(List<String> items) {
  final seen = <String>{};
  final result = <String>[];
  for (final item in items) {
    if (seen.add(item)) {
      result.add(item);
    }
  }
  return result;
}

Future<List<String>> _sanitizeDownloadQueue(List<String> queue) async {
  final nonEmpty =
      queue.where((cameraName) => cameraName.trim().isNotEmpty).toList();
  final prefs = SharedPreferencesAsync();
  final cameraSet = await prefs.getStringList(PrefKeys.cameraSet) ?? [];
  if (cameraSet.isEmpty) {
    if (nonEmpty.length != queue.length) {
      Log.w("Dropping empty camera names from download queue");
    }
    return _dedupePreserveOrder(nonEmpty);
  }

  final cameraSetLookup = cameraSet.toSet();
  final filtered =
      nonEmpty
          .where((cameraName) => cameraSetLookup.contains(cameraName))
          .toList();
  final dropped = nonEmpty.where((c) => !cameraSetLookup.contains(c)).toList();
  if (dropped.isNotEmpty) {
    Log.w("Dropping unknown cameras from download queue: $dropped");
  }
  return _dedupePreserveOrder(filtered);
}

//TODO: What if we miss a notification and don't get one for a long time? Should we occasionally query? What about if the user is in the app without any notifications?

Future<bool> retrieveVideos(String cameraName) async {
  Log.d("Entered for $cameraName");
  await DownloadStatus.markActive(cameraName, true);
  var epoch = await readEpoch(cameraName, "video");
  const downloadTimeout = Duration(seconds: 60);

  // We could crash/be terminated at any point during execution.
  // We need to perform the following steps carefully so that we
  // don't end up with a "fatal crash point", i.e., a crash that
  // will corrupt the MLS channel for good. For example, imagine
  // that we download the video and delete it from the server and
  // then we crash before decrypting it. At that point, the video
  // file, which includes the MLS commit msg, is gone and we won't
  // be able to decrypt any other videos on that channel anymore.
  // So here's the order of steps that should work:
  // 1. Download the video
  // 2. Decrypt the video (which merges the MLS commit)
  //    We should not terminate the loop if this step fails
  //    since that could happen if we previously crashed between
  //    steps 2 and 3.
  // 3. Increase epoch number in shared preferences
  // 4. Delete file from server

  try {
    while (true) {
      Log.d(
        "Trying to download video for epoch $epoch with $cameraName and encVideo$epoch",
      );

      final assumedEpoch = epoch > 0 ? epoch - 1 : 0;
      final fileName = "encVideo$epoch";
      final downloadSw = Stopwatch()..start();
      var result = await HttpClientService.instance.download(
        destinationFile: fileName,
        cameraName: cameraName,
        serverFile: epoch.toString(),
        type: Group.motion,
        timeout: downloadTimeout,
      );
      downloadSw.stop();
      if (!kReleaseMode) {
        Log.d(
          "[perf] Download motion $cameraName epoch $epoch in ${downloadSw.elapsedMilliseconds}ms (ok=${result.isSuccess})",
        );
      }

      if (result.isSuccess) {
        Log.d("Success!");
        var file = result.value!.file!;
        final decryptSw = Stopwatch()..start();
        var decFileName = await decryptVideo(
          cameraName: cameraName,
          encFilename: fileName,
          assumedEpoch: BigInt.from(assumedEpoch),
        );
        decryptSw.stop();
        if (!kReleaseMode) {
          Log.d(
            "[perf] Decrypt motion $cameraName $fileName in ${decryptSw.elapsedMilliseconds}ms (result=$decFileName)",
          );
        }
        if (decFileName.startsWith("Error")) {
          Log.w("Decrypt failed for $cameraName epoch $epoch: $decFileName");
          if (_isEpochMismatch(decFileName)) {
            final hasMarker = await hasEpochMarker(cameraName, "motion", epoch);
            if (hasMarker) {
              Log.w(
                "Epoch mismatch for $cameraName epoch $epoch but marker exists; treating as duplicate",
              );
              await file.delete();
              await writeEpoch(cameraName, "video", epoch + 1);
              await HttpClientService.instance.delete(
                destinationFile: fileName,
                cameraName: cameraName,
                serverFile: epoch.toString(),
                type: Group.motion,
              );
              epoch += 1;
              continue;
            }
          }
          final forceOk = await _maybeForceInit(cameraName, "decrypt_video");
          if (forceOk) {
            final retrySw = Stopwatch()..start();
            decFileName = await decryptVideo(
              cameraName: cameraName,
              encFilename: fileName,
              assumedEpoch: BigInt.from(assumedEpoch),
            );
            retrySw.stop();
            if (!kReleaseMode) {
              Log.d(
                "[perf] Decrypt motion retry $cameraName $fileName in ${retrySw.elapsedMilliseconds}ms (result=$decFileName)",
              );
            }
          }
        }

        if (decFileName.startsWith("Error")) {
          Log.e(
            "Decrypt failed for $cameraName epoch $epoch; leaving epoch unchanged",
          );
          return false;
        }

        Log.d("Dec file name = $decFileName");

        // Delete only after successful decrypt to avoid losing MLS commits.
        await file.delete();

        Log.d("Received 100%");

        if (decFileName != "Duplicate") {
          final baseDir = await getApplicationDocumentsDirectory();

          final filePath = p.join(
            baseDir.path,
            'waiting',
            'camera_$cameraName',
            decFileName,
          );

          final parentDir = Directory(p.dirname(filePath));
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }

          // Write an empty file to this pending directory to signal that it needs to be processed to our main processing thread (upon app startup, etc)
          // TODO: We should check if this fails and make contingencies.

          final creationIndicationFile = File(filePath);
          if (!await creationIndicationFile.exists()) {
            await creationIndicationFile.create();
          }

          SendPort? port = IsolateNameServer.lookupPortByName(
            'queue_processor_signal_port',
          );
          port?.send('signal_new_file');

          if (UiState.isBindingReady) {
            camerasPageKey.currentState?.invalidateThumbnail(cameraName);
          } else {
            Log.d("Skipping thumbnail invalidate; UI not initialized");
          }
        }

        await writeEpoch(cameraName, "video", epoch + 1);

        await HttpClientService.instance.delete(
          destinationFile: fileName,
          cameraName: cameraName,
          serverFile: epoch.toString(),
          type: Group.motion,
        );

        epoch += 1;
      } else {
        Log.d("Failed here");
        // We keep trying until hitting an error. Allows us to catch up on epochs.
        break;
      }
    }

    Log.d("Finished downloading for $cameraName");
    return true; // TODO: We may wish to utilize a check in the future on if something truly failed that could be retried, so this is left here as an architecture to make that happen
  } finally {
    await DownloadStatus.markActive(cameraName, false);
  }
}
