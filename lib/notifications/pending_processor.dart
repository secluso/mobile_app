//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/routes/camera/view_camera.dart';

Map<String, dynamic> _collectPendingWork(String baseDirPath) {
  final items = <Map<String, dynamic>>[];
  final errors = <String>[];
  final queueDir = Directory(p.join(baseDirPath, 'waiting'));

  if (!queueDir.existsSync()) {
    return {'items': items, 'errors': errors};
  }

  final files = queueDir.listSync(recursive: true, followLinks: false);
  for (final entry in files) {
    if (entry is! File) continue;

    final videoFile = p.basename(entry.path);
    if (videoFile.startsWith(".") ||
        videoFile.startsWith("meta_") ||
        !videoFile.endsWith(".mp4")) {
      continue;
    }

    final cameraName =
        p.basename(p.dirname(entry.path)).replaceFirst('camera_', '');

    final baseName = p.basenameWithoutExtension(videoFile);
    final ts = baseName.startsWith("video_") ? baseName.substring(6) : baseName;
    final metaFile = File(
      p.join(baseDirPath, 'waiting', 'meta', 'meta_$ts.txt'),
    );
    final metaExists = metaFile.existsSync();
    var metaParsed = false;
    var metaPending = false;
    var detections = <String>[];
    var metaAgeMs = 0;

    if (metaExists) {
      try {
        final stat = metaFile.statSync();
        metaAgeMs =
            DateTime.now().millisecondsSinceEpoch -
            stat.modified.millisecondsSinceEpoch;
        final raw = metaFile.readAsStringSync();
        if (raw.trim().isEmpty) {
          metaPending = true;
        } else {
          final List<dynamic> decoded = jsonDecode(raw);
          detections = decoded.cast<String>();
          metaParsed = true;
        }
      } catch (_) {
        // Likely still being written; retry on next pass.
        metaPending = true;
      }
    }

    items.add({
      'cameraName': cameraName,
      'videoFile': videoFile,
      'pendingPath': entry.path,
      'metaPath': metaExists ? metaFile.path : null,
      'metaParsed': metaParsed,
      'metaPending': metaPending,
      'metaAgeMs': metaAgeMs,
      'detections': detections,
    });
  }

  return {'items': items, 'errors': errors};
}

@pragma('vm:entry-point')
void _collectPendingWorkEntry(Map<String, dynamic> message) {
  final SendPort sendPort = message['sendPort'] as SendPort;
  try {
    final baseDirPath = message['baseDirPath'] as String;
    sendPort.send(_collectPendingWork(baseDirPath));
  } catch (e, st) {
    sendPort.send({'error': e.toString(), 'stack': st.toString()});
  }
}

/// Used to fix Android's background process not being allowed to acquire ObjectBox references. We store temporary files for each video that needs to be processed later and strictly have the main isolate add them to the database.
class QueueProcessor {
  static final QueueProcessor instance = QueueProcessor._();

  final StreamController<void> _signalController = StreamController.broadcast();
  bool _isRunning = false;
  bool _isStarted = false;
  static const int _metaGraceMs = 3000;

  QueueProcessor._() {
    Log.d('New instance created');
  }

  /// Must be called from the main isolate
  void start() {
    Log.d("start()");
    if (_isStarted) return;
    _isStarted = true;
    Log.d("Turning pending file checker on");

    _signalController.stream.listen((_) async {
      Log.d("Received signal!");
      if (_isRunning) return;
      _isRunning = true;

      try {
        await _processPendingFiles();
      } catch (e, st) {
        Log.e("Signal Stream Error: $e\n$st");
      } finally {
        Log.d("Turning pending file checker off");
        _isRunning = false;
      }
    });
  }

  void signalNewFile() {
    Log.d("Method called");
    _signalController.add(null);
  }

  Future<void> _processPendingFiles() async {
    try {
      await AppStores.init();
    } catch (e, st) {
      Log.e("Failed to initialize AppStores: $e\n$st");
      return;
    }
    if (!AppStores.isInitialized) {
      Log.e("AppStores not initialized; skipping pending processing");
      return;
    }

    final baseDir = await getApplicationDocumentsDirectory();
    final receivePort = ReceivePort();
    try {
      await Isolate.spawn(_collectPendingWorkEntry, {
        'sendPort': receivePort.sendPort,
        'baseDirPath': baseDir.path,
      });
    } catch (e, st) {
      receivePort.close();
      Log.e("Failed to spawn pending worker: $e\n$st");
      return;
    }

    final result = await receivePort.first;
    receivePort.close();

    if (result is Map && result['error'] != null) {
      Log.e(
        "Pending worker failed: ${result['error']}\n${result['stack'] ?? ''}",
      );
      return;
    }

    final itemsRaw =
        (result is Map ? result['items'] : null) as List? ?? const [];
    final errors =
        (result is Map ? result['errors'] : null) as List? ?? const [];

    for (final error in errors) {
      if (error is String && error.isNotEmpty) {
        Log.e(error);
      }
    }

    if (itemsRaw.isEmpty) return;

    final items = <Map<String, dynamic>>[];
    for (final item in itemsRaw) {
      if (item is Map) {
        items.add(item.cast<String, dynamic>());
      }
    }

    if (items.isEmpty) return;

    final AppStores stores;
    try {
      stores = AppStores.instance;
    } catch (e, st) {
      Log.e("AppStores instance unavailable: $e\n$st");
      return;
    }

    final cameraBox = stores.cameraStore.box<Camera>();
    final videoBox = stores.videoStore.box<Video>();
    final detectionBox = stores.detectionStore.box<Detection>();
    final cameras = await cameraBox.getAllAsync();
    final cameraByName = {for (final cam in cameras) cam.name: cam};

    final videosToPut = <Video>[];
    final detectionsToPut = <Detection>[];
    final camerasToUpdate = <Camera>[];
    final updatedCameraNames = <String>{};
    final pendingPathsToDelete = <String>[];
    final metaPathsToDelete = <String>[];

    for (final item in items) {
      final cameraName = item['cameraName'] as String?;
      final videoFile = item['videoFile'] as String?;
      final pendingPath = item['pendingPath'] as String?;
      final metaPath = item['metaPath'] as String?;
      final metaParsed = item['metaParsed'] == true;
      final metaPending = item['metaPending'] == true;
      final metaAgeMs = item['metaAgeMs'] as int? ?? 0;
      final detections =
          (item['detections'] as List?)?.cast<String>() ?? const [];

      if (metaPath != null && metaPending && metaAgeMs < _metaGraceMs) {
        // Wait for meta to finish writing.
        continue;
      }

      final discardMeta =
          metaPath != null && metaPending && metaAgeMs >= _metaGraceMs;

      if (cameraName == null || videoFile == null) {
        if (pendingPath != null) {
          pendingPathsToDelete.add(pendingPath);
        }
        if ((metaParsed || discardMeta) && metaPath != null) {
          metaPathsToDelete.add(metaPath);
        }
        continue;
      }

      final camera = cameraByName[cameraName];
      if (camera == null) {
        Log.e(
          "Camera entity is null in database. This shouldn't be possible. Camera: $cameraName Video: $videoFile",
        );
        if (pendingPath != null) {
          pendingPathsToDelete.add(pendingPath);
        }
        if ((metaParsed || discardMeta) && metaPath != null) {
          metaPathsToDelete.add(metaPath);
        }
        continue;
      }

      videosToPut.add(Video(cameraName, videoFile, true, true));

      for (final d in detections) {
        detectionsToPut.add(
          Detection(camera: cameraName, videoFile: videoFile, type: d),
        );
      }

      if (!camera.unreadMessages) {
        camera.unreadMessages = true;
        camerasToUpdate.add(camera);
      }

      updatedCameraNames.add(cameraName);
      if (pendingPath != null) {
        pendingPathsToDelete.add(pendingPath);
      }
      if ((metaParsed || discardMeta) && metaPath != null) {
        metaPathsToDelete.add(metaPath);
      }
    }

    if (videosToPut.isNotEmpty) {
      await videoBox.putManyAsync(videosToPut);
    }
    if (detectionsToPut.isNotEmpty) {
      await detectionBox.putManyAsync(detectionsToPut);
    }
    if (camerasToUpdate.isNotEmpty) {
      await cameraBox.putManyAsync(camerasToUpdate);
    }

    for (final path in pendingPathsToDelete) {
      try {
        await File(path).delete();
      } catch (e) {
        Log.e("Error deleting pending file $path: $e");
      }
    }
    for (final path in metaPathsToDelete) {
      try {
        await File(path).delete();
      } catch (e) {
        Log.e("Error deleting meta file $path: $e");
      }
    }

    if (updatedCameraNames.isEmpty) return;

    final currentState = globalCameraViewPageState;
    final currentCamera = currentState?.widget.cameraName;
    if (currentState?.mounted == true &&
        currentCamera != null &&
        updatedCameraNames.contains(currentCamera)) {
      currentState?.reloadVideos();
    }
  }

  void dispose() {
    _signalController.close();
  }
}
