import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';

import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/routes/camera/view_camera.dart';
import '../../objectbox.g.dart';

/// Used to fix Android's background process not being allowed to acquire ObjectBox references. We store temporary files for each video that needs to be processed later and strictly have the main isolate add them to the database.
class QueueProcessor {
  static final QueueProcessor instance = QueueProcessor._();

  final StreamController<void> _signalController = StreamController.broadcast();
  bool _isRunning = false;
  bool _isStarted = false;

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
    final baseDir = await getApplicationDocumentsDirectory();
    final queueDir = Directory(p.join(baseDir.path, 'waiting'));

    if (!await queueDir.exists()) return;

    final files = await queueDir.list(recursive: true).toList();

    for (var file in files) {
      if (file is File) {
        try {
          final cameraName = p
              .basename(p.dirname(file.path))
              .replaceFirst('camera_', '');
          final videoFile = p.basename(file.path);

          if (!videoFile.startsWith(".") && videoFile.endsWith(".mp4")) {
            Log.d(
              "Camera name for pending file: $cameraName, video file: $videoFile",
            );

            final box = AppStores.instance.videoStore.box<Video>();
            var video = Video(cameraName, videoFile, true, true);
            box.put(video);

            try {
              final baseName = p.basenameWithoutExtension(videoFile);
              final ts =
                  baseName.startsWith("video_")
                      ? baseName.substring(6)
                      : baseName;

              final metaFile = File(
                p.join(baseDir.path, 'waiting', 'meta', 'meta_$ts.txt'),
              );

              if (!await metaFile.exists()) {
                Log.d(
                  "No meta file for $videoFile (expected: ${metaFile.path})",
                );
              } else {
                final raw = await metaFile.readAsString();
                Log.d("Meta file (${metaFile.path}) contents:\n$raw");

                final List<dynamic> decoded = jsonDecode(raw);
                final detections = decoded.cast<String>();

                final detectionBox =
                    AppStores.instance.detectionStore.box<Detection>();
                for (final d in detections) {
                  final detection = Detection(
                    camera: cameraName,
                    videoFile: videoFile,
                    type: d, // lowercase string from Rust
                  );
                  final id = detectionBox.put(detection);
                  Log.d('Detection put id=$id type="$d" video="$videoFile"');
                }

                await metaFile.delete();
                Log.d("Saved ${detections.length} detection(s) for $videoFile");
              }
            } catch (e, st) {
              Log.e("Failed to process meta for $videoFile: $e\n$st");
            }

            final cameraBox = AppStores.instance.cameraStore.box<Camera>();
            final cameraQuery =
                cameraBox.query(Camera_.name.equals(cameraName)).build();

            final foundCamera = cameraQuery.findFirst();
            cameraQuery.close();

            if (foundCamera == null) {
              Log.e(
                "Camera entity is null in database. This shouldn't be possible. Camera: $cameraName Video: $videoFile",
              );
              await file.delete();

              continue;
            }

            if (!foundCamera.unreadMessages) {
              Log.d("Setting camera $cameraName to have unreadMessages = true");
              foundCamera.unreadMessages = true;
              cameraBox.put(foundCamera);
            } else {
              Log.d("Camera was already set on unreadMessages = true");
            }

            if (globalCameraViewPageState?.mounted == true &&
                globalCameraViewPageState?.widget.cameraName == cameraName) {
              globalCameraViewPageState?.reloadVideos();
            } else if (globalCameraViewPageState?.mounted == false) {
              Log.d("Not reloading current camera page - not mounted");
            } else {
              final currentPage = globalCameraViewPageState?.widget.cameraName;
              Log.d(
                "Not reloading current camera page - name doesn't match. $currentPage, $cameraName",
              );
            }

            await file.delete();
          } else if (!videoFile.startsWith("meta_")) {
            Log.d(
              "Disregarding file $videoFile for $cameraName in update pending logic",
            );
          }
        } catch (e) {
          Log.e("Error processing ${file.path}: $e");
        }
      }
    }
  }

  void dispose() {
    _signalController.close();
  }
}
