//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/utilities/logger.dart';

class AppPaths {
  AppPaths._();

  static const MethodChannel _storageChannel = MethodChannel(
    'secluso.com/storage',
  );
  static const Duration _backupSweepInterval = Duration(minutes: 1);

  static Future<Directory>? _dataDirectoryFuture;
  static DateTime? _lastBackupSweepAt;
  static Future<void>? _backupSweepFuture;

  static Future<Directory> dataDirectory() async {
    final directory = await (_dataDirectoryFuture ??= _resolveDataDirectory());
    await _refreshBackupExclusionIfNeeded(directory);
    return directory;
  }

  static Future<Directory> _resolveDataDirectory() async {
    final rootDir =
        Platform.isIOS
            ? await getApplicationSupportDirectory()
            : await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(rootDir.path, 'secluso'));
    await dataDir.create(recursive: true);
    Log.i(
      '[storage] Using app data directory ${dataDir.path} (platform=${Platform.operatingSystem})',
    );
    await _forceRefreshBackupExclusion(dataDir);
    return dataDir;
  }

  static Future<void> _refreshBackupExclusionIfNeeded(
    Directory directory,
  ) async {
    if (!Platform.isIOS) return;
    final now = DateTime.now();
    final lastSweepAt = _lastBackupSweepAt;
    if (lastSweepAt != null &&
        now.difference(lastSweepAt) < _backupSweepInterval) {
      return;
    }
    if (_backupSweepFuture != null) {
      await _backupSweepFuture;
      return;
    }
    final future = _forceRefreshBackupExclusion(directory);
    _backupSweepFuture = future;
    try {
      await future;
    } finally {
      if (identical(_backupSweepFuture, future)) {
        _backupSweepFuture = null;
      }
    }
  }

  static Future<void> _forceRefreshBackupExclusion(Directory directory) async {
    if (!Platform.isIOS) return;
    try {
      await _storageChannel.invokeMethod<void>('excludeTreeFromBackup', {
        'path': directory.path,
      });
      final excluded =
          await _storageChannel.invokeMethod<bool>('isExcludedFromBackup', {
            'path': directory.path,
          }) ??
          false;
      _lastBackupSweepAt = DateTime.now();
      Log.i(
        '[storage] Backup exclusion sweep complete for ${directory.path} (excluded=$excluded)',
      );
    } catch (error) {
      Log.w(
        '[storage] Failed to refresh backup exclusion for ${directory.path}: $error',
      );
    }
  }
}
