//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/src/rust/api.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:typed_data';
import 'package:secluso_flutter/utilities/rust_util.dart';

class ThumbnailManager {
  static const Duration _stableWaitTimeout = Duration(seconds: 2);
  static const Duration _stableWaitPoll = Duration(milliseconds: 120);
  static const int _minPngSizeBytes = 32;

  static const List<int> _pngSignature = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  static bool _looksLikePngHeader(Uint8List bytes) {
    if (bytes.length < _pngSignature.length) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  static Future<bool> _waitForStablePng(String filePath) async {
    final file = File(filePath);
    final deadline = DateTime.now().add(_stableWaitTimeout);
    int? lastSize;

    while (DateTime.now().isBefore(deadline)) {
      if (!await file.exists()) return false;
      final stat = await file.stat();
      final size = stat.size;
      if (size >= _minPngSizeBytes &&
          lastSize != null &&
          size == lastSize) {
        RandomAccessFile? raf;
        try {
          raf = await file.open(mode: FileMode.read);
          final header = await raf.read(_pngSignature.length);
          return _looksLikePngHeader(header);
        } catch (_) {
          return false;
        } finally {
          await raf?.close();
        }
      }
      lastSize = size;
      await Future.delayed(_stableWaitPoll);
    }
    return false;
  }

  // Return early if the specified timestamp is found (but still continue as long as possible)
  static Future<bool> checkThumbnailsForCamera(
    String camera,
    String timestamp,
  ) async {
    final completer = Completer<bool>();

    // Check if the file already exists in the thumbnails folder
    final baseDir = await getApplicationDocumentsDirectory();

    final filePath = p.join(
      baseDir.path,
      'camera_dir_$camera',
      'videos',
      "thumbnail_$timestamp.png",
    );

    if (await File(filePath).exists()) {
      return true;
    }

    // If we can't get the corresponding thumbnail in 15 seconds, we send the notification without it.
    final timeBudget = Duration(seconds: 15);

    unawaited(
      _session(
        camera: camera,
        timeBudget: timeBudget,
        targetTimestamp: timestamp,
        onTargetReady: (success) {
          if (!completer.isCompleted) completer.complete(success);
        },
      ),
    );

    // If it isn't done in time, we return false.
    Future.delayed(timeBudget).then((_) {
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  static Future<void> checkThumbnailsForAll() async {
    // Call the endpoint asking for the epochs that haven't been used in over 5 mins. This indicates we likely won't get a notification for it.
    // See if we have the epoch beforehand. If we do, we download it.

    var cameraNamesResult = await HttpClientService.instance
        .bulkCheckAvailableCameras(5 * 60);

    if (cameraNamesResult.isFailure ||
        (cameraNamesResult.isSuccess && cameraNamesResult.value!.isEmpty)) {
      return;
    }

    var cameraNames = cameraNamesResult.value!;
    for (String camera in cameraNames) {
      // Should this be awaited?
      _session(
        camera: camera,
        timeBudget: Duration(seconds: 120),
        targetTimestamp:
            "1", // This is never possible, so it'll go until it runs out
        onTargetReady: (success) {},
      );
    }
  }

  static Future<void> _session({
    required String camera,
    required Duration timeBudget,
    required String targetTimestamp,
    required void Function(bool)
    onTargetReady, //true = found, false = not found
  }) async {
    Log.d("Entered thumbnail session");
    // There's a chance a thumbnail could be requested multiple times at once for a given camera. So we need to lock this function per-camera to ensure that doesn't occur.
    if (await lock("thumbnail$camera.lock")) {
      try {
        if (!await initialize(camera)) {
          Log.e("Thumbnail init failed for camera $camera");
          return;
        }

        final sw = Stopwatch()..start();

        while (sw.elapsed <= timeBudget) {
          // Epoch for this starts at 2 when not set from before.
          final epoch = await readEpoch(camera, "thumbnail");
          Log.d("Thumbnail Epoch = $epoch");
          final fileName = "encThumbnail$epoch";
          var result = await HttpClientService.instance.download(
            destinationFile: fileName,
            cameraName: camera,
            serverFile: epoch.toString(),
            type: Group.thumbnail,
          );

          if (result.isFailure) break;

          Log.d("Proceeding after thumbnail download");
          final baseDir = await getApplicationDocumentsDirectory();
          final metaDir = Directory(p.join(baseDir.path, 'waiting', 'meta'));
          await metaDir.create(recursive: true);

          // Decode the thumbnail
          var file = result.value!.file!;
          var decFileName = await decryptThumbnail(
            cameraName: camera,
            encFilename: fileName,
            pendingMetaDirectory: metaDir.path,
          );

          Log.d("Thumbnail dec file name = $decFileName");

          if (decFileName != "Error") {
            final decPath = p.join(
              baseDir.path,
              'camera_dir_$camera',
              'videos',
              decFileName,
            );
            final ready = await _waitForStablePng(decPath);
            if (!ready) {
              Log.e("Thumbnail file not ready or invalid: $decPath");
              return;
            }

            await file.delete();
            var result = decFileName == "thumbnail_$targetTimestamp.png";
            Log.d(
              "Received thumbnail 100%, comparing to thumbnail_$targetTimestamp.png ($result)",
            );
            ThumbnailNotifier.instance.notify(camera);

            if (decFileName == "thumbnail_$targetTimestamp.png") {
              Log.d("Received target thumbnail");
              onTargetReady(true);
            }
          } else {
            // TODO: What do we do here? We probably shouldn't increment the epoch if we hit an error..
            return;
          }

          await writeEpoch(camera, "thumbnail", epoch + 1);

          await HttpClientService.instance.delete(
            destinationFile: fileName,
            cameraName: camera,
            serverFile: epoch.toString(),
            type: Group.thumbnail,
          );
        }
      } finally {
        await unlock(
          "thumbnail$camera.lock",
        ); // Always ensure this unlocks, even on exceptions
      }
    } else {
      Log.e("Failed to acquire thumbnail session lock");
    }
  }

  // RetriveAllThumbnails of a camera
  static Future<void> retrieveThumbnails({required String camera}) async {
    Log.d("Entered retrieveThumbnails");
    if (await lock("thumbnail$camera.lock")) {
      try {
        if (!await initialize(camera)) {
          Log.e("Thumbnail init failed for camera $camera");
          return;
        }

        // Epoch for this starts at 2 when not set from before.
        final epoch = await readEpoch(camera, "thumbnail");
        Log.d("Thumbnail Epoch = $epoch");
        final fileName = "encThumbnail$epoch";
        var result = await HttpClientService.instance.download(
          destinationFile: fileName,
          cameraName: camera,
          serverFile: epoch.toString(),
          type: Group.thumbnail,
        );

        if (result.isFailure) return;

        Log.d("Proceeding after thumbnail download");
        final baseDir = await getApplicationDocumentsDirectory();
        final metaDir = Directory(p.join(baseDir.path, 'waiting', 'meta'));
        await metaDir.create(recursive: true);

        // Decode the thumbnail
        var file = result.value!.file!;
        var decFileName = await decryptThumbnail(
          cameraName: camera,
          encFilename: fileName,
          pendingMetaDirectory: metaDir.path,
        );

        Log.d("Thumbnail dec file name = $decFileName");

        if (decFileName != "Error") {
          final decPath = p.join(
            baseDir.path,
            'camera_dir_$camera',
            'videos',
            decFileName,
          );
          final ready = await _waitForStablePng(decPath);
          if (!ready) {
            Log.e("Thumbnail file not ready or invalid: $decPath");
            return;
          }

          await file.delete();
          ThumbnailNotifier.instance.notify(camera);
        } else {
          // TODO: What do we do here? We probably shouldn't increment the epoch if we hit an error..
          return;
        }

        await writeEpoch(camera, "thumbnail", epoch + 1);

        await HttpClientService.instance.delete(
          destinationFile: fileName,
          cameraName: camera,
          serverFile: epoch.toString(),
          type: Group.thumbnail,
        );
      } finally {
        await unlock(
          "thumbnail$camera.lock",
        ); // Always ensure this unlocks, even on exceptions
      }
    } else {
      Log.e("Failed to acquire thumbnail session lock");
    }
  }
}
