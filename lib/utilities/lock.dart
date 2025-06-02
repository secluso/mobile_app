import 'package:path_provider/path_provider.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'package:path/path.dart' as p;
import 'package:privastead_flutter/src/rust/api/lock_manager.dart';
import 'dart:io';

/// Acquire a file lock via Rust-code
Future<bool> lock(String name) async {
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
  return await acquireLock(path: lock);
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
