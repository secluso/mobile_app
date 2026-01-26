//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String _markerName(String kind, int epoch) {
  return ".epoch_${kind}_$epoch.done";
}

Future<File> _markerFile(String cameraName, String kind, int epoch) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = p.join(base.path, 'camera_dir_$cameraName', 'videos');
  return File(p.join(dir, _markerName(kind, epoch)));
}

Future<bool> hasEpochMarker(String cameraName, String kind, int epoch) async {
  final file = await _markerFile(cameraName, kind, epoch);
  return file.exists();
}

Future<String?> readEpochMarker(String cameraName, String kind, int epoch) async {
  final file = await _markerFile(cameraName, kind, epoch);
  if (!await file.exists()) {
    return null;
  }
  try {
    final content = await file.readAsString();
    final trimmed = content.trim();
    return trimmed.isEmpty ? null : trimmed;
  } catch (_) {
    return null;
  }
}
