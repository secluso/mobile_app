import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/routes/camera/view_camera.dart';
import '../../objectbox.g.dart';

/// Used to fix Android's background process not being allowed to acquire ObjectBox references. We store temporary files for each video that needs to be processed later and strictly have the main isolate add them to the database.
class QueueProcessor {
  static final QueueProcessor instance = QueueProcessor._();

  final StreamController<void> _signalController = StreamController.broadcast();
  bool _isRunning = false;
  bool _isStarted = false;

  QueueProcessor._() {
    print('[QueueProcessor] New instance created');
  }

  /// Must be called from the main isolate
  void start() {
    print("Pending Processor: start()");
    if (_isStarted) return;
    _isStarted = true;
    print("Turning pending file checker on");

    _signalController.stream.listen((_) async {
      print("Received signal!");
      if (_isRunning) return;
      _isRunning = true;

      try {
        await _processPendingFiles();
      } catch (e, st) {
        print("Processor error: $e\n$st");
      } finally {
        print("Turning pending file checker off");
        _isRunning = false;
      }
    });
  }

  void signalNewFile() {
    print("Signaling new file");
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
          print("Starting to process a pending file");
          // TODO: Potentailly store metadata in the pending file if need be.
          final cameraName = p
              .basename(p.dirname(file.path))
              .replaceFirst('camera_', '');
          final videoFile = p.basename(file.path);

          if (!videoFile.startsWith(".") && videoFile.endsWith(".mp4")) {
            print(
              "Camera name for pending file: $cameraName, video file: $videoFile",
            );

            final box = AppStores.instance.videoStore.box<Video>();
            var video = Video(cameraName, videoFile, true, true);
            box.put(video);

            final cameraBox = AppStores.instance.cameraStore.box<Camera>();
            final cameraQuery =
                cameraBox.query(Camera_.name.equals(cameraName)).build();

            final foundCamera = cameraQuery.findFirst();
            cameraQuery.close();

            if (foundCamera == null) {
              print(
                "Camera entity is null in database. This shouldn't be possible. Camera: $cameraName Video: $videoFile",
              );
              await file.delete();

              continue;
            }

            if (!foundCamera.unreadMessages) {
              print("Setting camera $cameraName to have unreadMessages = true");
              foundCamera.unreadMessages = true;
              cameraBox.put(foundCamera);
            } else {
              print("Camera was already set on unreadMessages = true");
            }

            if (globalCameraViewPageState?.mounted == true &&
                globalCameraViewPageState?.widget.cameraName == cameraName) {
              globalCameraViewPageState?.reloadVideos();
            } else if (globalCameraViewPageState?.mounted == false) {
              print("Not reloading current camera page - not mounted");
            } else {
              final currentPage = globalCameraViewPageState?.widget.cameraName;
              print(
                "Not reloading current camera page - name doesn't match. $currentPage, $cameraName",
              );
            }

            await file.delete();
          } else {
            print(
              "Disregarding file $videoFile for $cameraName in update pending logic",
            );
          }
        } catch (e) {
          print("Error processing ${file.path}: $e");
        }
      }
    }
  }

  void dispose() {
    _signalController.close();
  }
}
