//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'app_stores.dart';

typedef Migration = Future<void> Function();

final List<Migration> migrations = [
  // Migration 1: Test migration to ensure system works properly in the event we need this.
  () async {
    final cameraBox = AppStores.instance.cameraStore.box<Camera>();
    final cameras = cameraBox.getAll();
    final List<Camera> patched = [];

    for (var cam in cameras) {
      try {
        cam.unreadMessages; // will throw if unreadMessages is null
      } catch (_) {
        cam.unreadMessages = false;
        patched.add(cam);
      }
    }

    if (patched.isNotEmpty) {
      cameraBox.putMany(patched);
      Log.d("Fixed ${patched.length} null unreadMessages values.");
    } else {
      Log.d("No null unreadMessages values found.");
    }
  },
];
