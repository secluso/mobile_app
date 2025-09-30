//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Reads the stored epoch for cameraName. Returns default value of 2 if missing
/// or unreadable. Type is either "video" or "thumbnail".
Future<int> readEpoch(String cameraName, String type, {int defaultValue = 2}) async {
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, 'camera_dir_$cameraName', 'epoch_$type');
  final f = File(path);

  try {
    if (!await f.exists()) return defaultValue;
    final txt = await f.readAsString();
    final v = int.tryParse(txt.trim());
    return v ?? defaultValue;
  } catch (_) {
    return defaultValue;
  }
}

/// Atomically writes value for cameraName and fsyncs the data to disk.
/// Type is either "video" or "thumbnail".
/// Steps:
/// 1) write to a temp file
/// 2) flush (fsync)
/// 3) close
/// 4) rename temp -> final (atomic on POSIX filesystems)
Future<void> writeEpoch(String cameraName, String type, int value) async {
  final dir = await getApplicationDocumentsDirectory();
  final cameraDir = Directory(p.join(dir.path, 'camera_dir_$cameraName'));
  if (!await cameraDir.exists()) {
    await cameraDir.create(recursive: true);
  }

  final finalPath = p.join(cameraDir.path, 'epoch_$type');
  final tmpPath   = '$finalPath.tmp';

  final tmpFile = File(tmpPath);
  final raf = await tmpFile.open(mode: FileMode.write);

  try {
    await raf.writeString('$value\n');

    await raf.flush();
  } finally {
    await raf.close();
  }

  await tmpFile.rename(finalPath);
}