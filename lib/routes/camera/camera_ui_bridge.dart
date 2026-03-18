//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import '../../objectbox.g.dart';

class CameraUiBridge {
  CameraUiBridge._();

  static Future<void> Function(String cameraName)? deleteCameraCallback;
  static VoidCallback? refreshCameraListCallback;
  static VoidCallback? refreshActivityCallback;
  static void Function(int index, {bool openRelayScanOnLoad})?
  switchShellTabCallback;

  static Future<void> deleteCamera(String cameraName) async {
    if (!AppStores.isInitialized) {
      await AppStores.init();
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName);
    await prefs.remove(PrefKeys.cameraStatusPrefix + cameraName);
    await prefs.remove(PrefKeys.numHeartbeatNotificationsPrefix + cameraName);
    await prefs.remove(PrefKeys.lastHeartbeatTimestampPrefix + cameraName);
    await prefs.remove(PrefKeys.firmwareVersionPrefix + cameraName);

    await deregisterCamera(cameraName: cameraName);
    invalidateCameraInit(cameraName);
    HttpClientService.instance.clearGroupNameCache(cameraName);

    final cameraBox = AppStores.instance.cameraStore.box<Camera>();
    final videoBox = AppStores.instance.videoStore.box<Video>();

    await prefs.remove('first_time_$cameraName');

    var existingCameraSet = prefs.getStringList(PrefKeys.cameraSet) ?? [];
    existingCameraSet.remove(cameraName);
    await prefs.setStringList(PrefKeys.cameraSet, existingCameraSet);

    for (final queueKey in [
      PrefKeys.downloadCameraQueue,
      PrefKeys.backupDownloadCameraQueue,
    ]) {
      final existingQueue = prefs.getStringList(queueKey);
      if (existingQueue == null) {
        continue;
      }
      final filteredQueue =
          existingQueue
              .where((queuedCamera) => queuedCamera != cameraName)
              .toList();
      if (filteredQueue.length != existingQueue.length) {
        if (filteredQueue.isEmpty) {
          await prefs.remove(queueKey);
        } else {
          await prefs.setStringList(queueKey, filteredQueue);
        }
      }
    }

    final query = cameraBox.query(Camera_.name.equals(cameraName)).build();
    final cams = query.find();
    query.close();
    for (final cam in cams) {
      cameraBox.remove(cam.id);
    }

    final videoQuery = videoBox.query(Video_.camera.equals(cameraName)).build();
    final videos = videoQuery.find();
    videoQuery.close();
    videoBox.removeMany(videos.map((v) => v.id).toList());

    final docsDir = await getApplicationDocumentsDirectory();
    final camDir = Directory(p.join(docsDir.path, 'camera_dir_$cameraName'));
    if (await camDir.exists()) {
      try {
        await camDir.delete(recursive: true);
        Log.d('Deleted camera folder: ${camDir.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }

    final lock = File(
      p.join(docsDir.path, 'locks', 'thumbnail$cameraName.lock'),
    );
    if (await lock.exists()) {
      await lock.delete();
    }

    final camDirPending = Directory(
      p.join(docsDir.path, 'waiting', 'camera_$cameraName'),
    );
    if (await camDirPending.exists()) {
      try {
        await camDirPending.delete(recursive: true);
        Log.d('Deleted camera waiting folder: ${camDirPending.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }
  }
}
