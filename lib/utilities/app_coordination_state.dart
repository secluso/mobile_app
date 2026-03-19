//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

import 'package:secluso_flutter/keys.dart';

class AppCoordinationState {
  AppCoordinationState._();

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static List<String> _normalizeList(Iterable<String>? values) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in values ?? const <String>[]) {
      final value = raw.trim();
      if (value.isEmpty || !seen.add(value)) {
        continue;
      }
      out.add(value);
    }
    return out;
  }

  static Future<List<String>> getCameraSet() async {
    final prefs = await _prefs();
    return _normalizeList(prefs.getStringList(PrefKeys.cameraSet));
  }

  static bool containsCameraInSnapshot(
    SharedPreferences prefs,
    String cameraName,
  ) {
    final normalizedName = cameraName.trim();
    if (normalizedName.isEmpty) {
      return false;
    }
    final cameraSet = _normalizeList(prefs.getStringList(PrefKeys.cameraSet));
    return cameraSet.contains(normalizedName);
  }

  static Future<bool> containsCamera(String cameraName) async {
    final prefs = await _prefs();
    return containsCameraInSnapshot(prefs, cameraName);
  }

  static Future<bool> addCamera(String cameraName) async {
    final normalizedName = cameraName.trim();
    if (normalizedName.isEmpty) {
      return false;
    }

    final prefs = await _prefs();
    final current = _normalizeList(prefs.getStringList(PrefKeys.cameraSet));
    if (current.contains(normalizedName)) {
      return false;
    }
    current.add(normalizedName);
    await prefs.setStringList(PrefKeys.cameraSet, current);
    return true;
  }

  static Future<bool> removeCamera(String cameraName) async {
    final normalizedName = cameraName.trim();
    final prefs = await _prefs();
    final current = _normalizeList(prefs.getStringList(PrefKeys.cameraSet));
    final changed = current.remove(normalizedName);
    if (!changed) {
      return false;
    }
    await prefs.setStringList(PrefKeys.cameraSet, current);
    return true;
  }

  static Future<List<String>> _getListKey(String key) async {
    final prefs = await _prefs();
    return _normalizeList(prefs.getStringList(key));
  }

  static Future<void> _writeListKey(String key, List<String> values) async {
    final prefs = await _prefs();
    final normalized = _normalizeList(values);
    if (normalized.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setStringList(key, normalized);
    }
  }

  static Future<List<String>> getDownloadQueue() =>
      _getListKey(PrefKeys.downloadCameraQueue);

  static Future<List<String>> getBackupDownloadQueue() =>
      _getListKey(PrefKeys.backupDownloadCameraQueue);

  static Future<bool> hasDownloadQueue() async {
    final queue = await getDownloadQueue();
    return queue.isNotEmpty;
  }

  static Future<bool> hasBackupDownloadQueue() async {
    final queue = await getBackupDownloadQueue();
    return queue.isNotEmpty;
  }

  static Future<bool> hasAnyDownloadQueue() async {
    return await hasDownloadQueue() || await hasBackupDownloadQueue();
  }

  static Future<void> setDownloadQueue(List<String> values) =>
      _writeListKey(PrefKeys.downloadCameraQueue, values);

  static Future<void> setBackupDownloadQueue(List<String> values) =>
      _writeListKey(PrefKeys.backupDownloadCameraQueue, values);

  static Future<void> clearDownloadQueue() async {
    final prefs = await _prefs();
    await prefs.remove(PrefKeys.downloadCameraQueue);
  }

  static Future<void> clearBackupDownloadQueue() async {
    final prefs = await _prefs();
    await prefs.remove(PrefKeys.backupDownloadCameraQueue);
  }

  static Future<void> clearDownloadQueues() async {
    final prefs = await _prefs();
    await prefs.remove(PrefKeys.downloadCameraQueue);
    await prefs.remove(PrefKeys.backupDownloadCameraQueue);
  }

  static Future<void> enqueueDownloadCamera(String cameraName) async {
    final normalizedName = cameraName.trim();
    if (normalizedName.isEmpty) {
      return;
    }

    final queue = await getDownloadQueue();
    if (queue.contains(normalizedName)) {
      return;
    }
    queue.add(normalizedName);
    await setDownloadQueue(queue);
  }

  static Future<void> removeCameraFromDownloadQueues(String cameraName) async {
    final normalizedName = cameraName.trim();
    if (normalizedName.isEmpty) {
      return;
    }

    final downloadQueue = await getDownloadQueue();
    downloadQueue.removeWhere((camera) => camera == normalizedName);
    await setDownloadQueue(downloadQueue);

    final backupQueue = await getBackupDownloadQueue();
    backupQueue.removeWhere((camera) => camera == normalizedName);
    await setBackupDownloadQueue(backupQueue);
  }
}
