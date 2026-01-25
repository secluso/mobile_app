//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:path/path.dart' as p;
import 'package:secluso_flutter/src/rust/api/lock_manager.dart';
import 'dart:io';

/// Acquire a file lock via Rust-code
Future<bool> lock(
  String name, {
  Duration timeout = const Duration(seconds: 10),
  Duration retryDelay = const Duration(milliseconds: 60),
}) async {
  Log.d("Acquiring lock");
  var lockParentDirectory = p.join(
    (await getApplicationDocumentsDirectory()).path,
    "locks",
  );
  var parentDirectoryFile = Directory(lockParentDirectory);
  if (!await parentDirectoryFile.exists()) {
    await parentDirectoryFile.create(recursive: true);
  }

  var lock = p.join(lockParentDirectory, name);
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    final ok = await tryAcquireLock(path: lock);
    if (ok) {
      if (sw.elapsedMilliseconds > 200) {
        Log.d("Lock $name acquired after ${sw.elapsedMilliseconds}ms");
      }
      return true;
    }
    await Future.delayed(retryDelay);
  }

  Log.w("Lock $name timeout after ${timeout.inSeconds}s");
  return false;
}

/// Release a previously acquried lock via Rust-code
Future<void> unlock(String name) async {
  Log.d("Releasing lock");
  var lockLocation = p.join(
    (await getApplicationDocumentsDirectory()).path,
    "locks",
    name,
  );

  await releaseLock(path: lockLocation);
}
