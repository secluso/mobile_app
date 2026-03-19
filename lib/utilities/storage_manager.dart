//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/utilities/logger.dart';

class StorageSummary {
  const StorageSummary({
    required this.totalBytes,
    required this.videoBytes,
    required this.thumbnailBytes,
    required this.encryptedBytes,
    required this.otherBytes,
    required this.videoCount,
    required this.thumbnailCount,
  });

  final int totalBytes;
  final int videoBytes;
  final int thumbnailBytes;
  final int encryptedBytes;
  final int otherBytes;
  final int videoCount;
  final int thumbnailCount;

  int get managedMediaBytes => videoBytes + thumbnailBytes + encryptedBytes;

  double get mediaShareOfAppData {
    if (totalBytes <= 0) return 0;
    return math.min(1, managedMediaBytes / totalBytes);
  }
}

class StorageCleanupResult {
  const StorageCleanupResult({
    required this.bytesFreed,
    required this.deletedVideos,
    required this.deletedThumbnails,
    required this.deletedTempFiles,
    required this.removedVideoRows,
    required this.removedDetectionRows,
  });

  final int bytesFreed;
  final int deletedVideos;
  final int deletedThumbnails;
  final int deletedTempFiles;
  final int removedVideoRows;
  final int removedDetectionRows;

  bool get didWork =>
      bytesFreed > 0 ||
      deletedVideos > 0 ||
      deletedThumbnails > 0 ||
      deletedTempFiles > 0 ||
      removedVideoRows > 0 ||
      removedDetectionRows > 0;
}

class StorageManager {
  StorageManager._();

  static const List<int> retentionOptions = [7, 30, 90];
  static const int defaultRetentionDays = 30;
  static const int _keepForeverSentinel = 0;

  static Future<StorageSummary> calculateSummary() async {
    final docsDir = await getApplicationDocumentsDirectory();
    if (!await docsDir.exists()) {
      return const StorageSummary(
        totalBytes: 0,
        videoBytes: 0,
        thumbnailBytes: 0,
        encryptedBytes: 0,
        otherBytes: 0,
        videoCount: 0,
        thumbnailCount: 0,
      );
    }

    var totalBytes = 0;
    var videoBytes = 0;
    var thumbnailBytes = 0;
    var encryptedBytes = 0;
    var otherBytes = 0;
    var videoCount = 0;
    var thumbnailCount = 0;

    await for (final entity in docsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      final size = stat.size;
      totalBytes += size;
      final relativePath = p.relative(entity.path, from: docsDir.path);
      final parts = p.split(relativePath);

      if (parts.length >= 3 &&
          parts[0].startsWith('camera_dir_') &&
          parts[1] == 'videos' &&
          parts[2].startsWith('video_') &&
          parts[2].endsWith('.mp4')) {
        videoBytes += size;
        videoCount += 1;
        continue;
      }

      if (parts.length >= 3 &&
          parts[0].startsWith('camera_dir_') &&
          parts[1] == 'videos' &&
          parts[2].startsWith('thumbnail_') &&
          parts[2].endsWith('.png')) {
        thumbnailBytes += size;
        thumbnailCount += 1;
        continue;
      }

      if (parts.length >= 3 &&
          parts[0].startsWith('camera_dir_') &&
          parts[1] == 'encrypted') {
        encryptedBytes += size;
        continue;
      }

      otherBytes += size;
    }

    return StorageSummary(
      totalBytes: totalBytes,
      videoBytes: videoBytes,
      thumbnailBytes: thumbnailBytes,
      encryptedBytes: encryptedBytes,
      otherBytes: otherBytes,
      videoCount: videoCount,
      thumbnailCount: thumbnailCount,
    );
  }

  static Future<bool> isAutoCleanupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PrefKeys.storageAutoCleanupEnabled) ?? true;
  }

  static Future<void> setAutoCleanupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefKeys.storageAutoCleanupEnabled, enabled);
  }

  static Future<int?> getRetentionDays() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(PrefKeys.storageRetentionDays)) {
      return defaultRetentionDays;
    }
    final value =
        prefs.getInt(PrefKeys.storageRetentionDays) ?? _keepForeverSentinel;
    return value <= 0 ? null : value;
  }

  static Future<void> setRetentionDays(int? days) async {
    final prefs = await SharedPreferences.getInstance();
    if (days == null) {
      await prefs.setInt(PrefKeys.storageRetentionDays, _keepForeverSentinel);
      return;
    }
    await prefs.setInt(PrefKeys.storageRetentionDays, days);
  }

  static Future<StorageCleanupResult> runAutomaticMaintenance() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(PrefKeys.storageAutoCleanupEnabled) ?? true;
    if (!enabled) {
      return _emptyCleanupResult();
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastRun = prefs.getInt(PrefKeys.storageLastCleanupMs) ?? 0;
    if (now - lastRun < const Duration(hours: 12).inMilliseconds) {
      return _emptyCleanupResult();
    }

    await prefs.setInt(PrefKeys.storageLastCleanupMs, now);

    final retentionValue =
        prefs.containsKey(PrefKeys.storageRetentionDays)
            ? (prefs.getInt(PrefKeys.storageRetentionDays) ??
                _keepForeverSentinel)
            : defaultRetentionDays;
    final result =
        retentionValue > 0
            ? await deleteVideosOlderThan(Duration(days: retentionValue))
            : _emptyCleanupResult();
    final orphanResult = await removeOrphanedEntries();
    return _mergeResults(result, orphanResult);
  }

  static Future<StorageCleanupResult> deleteVideosOlderThan(
    Duration age,
  ) async {
    final cutoff = DateTime.now().toUtc().subtract(age);
    return _deleteVideosWhere((video) {
      final timestamp = _timestampFromVideoName(video.video);
      return timestamp != null && timestamp.isBefore(cutoff);
    });
  }

  static Future<StorageCleanupResult> deleteAllVideos() async {
    return _deleteVideosWhere((_) => true);
  }

  static Future<StorageCleanupResult> clearAllThumbnails() async {
    final docsDir = await getApplicationDocumentsDirectory();
    var bytesFreed = 0;
    var deletedThumbnails = 0;

    await for (final entity in docsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final basename = p.basename(entity.path);
      if (!basename.startsWith('thumbnail_') || !basename.endsWith('.png')) {
        continue;
      }
      bytesFreed += await _safeDeleteFile(entity);
      deletedThumbnails += 1;
    }

    await _deleteEpochMarkersReferencing((name) {
      return name.startsWith('thumbnail_') && name.endsWith('.png');
    });

    return StorageCleanupResult(
      bytesFreed: bytesFreed,
      deletedVideos: 0,
      deletedThumbnails: deletedThumbnails,
      deletedTempFiles: 0,
      removedVideoRows: 0,
      removedDetectionRows: 0,
    );
  }

  static Future<StorageCleanupResult> clearEncryptedTempFiles() async {
    final docsDir = await getApplicationDocumentsDirectory();
    var bytesFreed = 0;
    var deletedTempFiles = 0;

    await for (final entity in docsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final parts = p.split(p.relative(entity.path, from: docsDir.path));
      if (parts.length >= 3 &&
          parts[0].startsWith('camera_dir_') &&
          parts[1] == 'encrypted') {
        bytesFreed += await _safeDeleteFile(entity);
        deletedTempFiles += 1;
      }
    }

    return StorageCleanupResult(
      bytesFreed: bytesFreed,
      deletedVideos: 0,
      deletedThumbnails: 0,
      deletedTempFiles: deletedTempFiles,
      removedVideoRows: 0,
      removedDetectionRows: 0,
    );
  }

  static Future<StorageCleanupResult> removeOrphanedEntries() async {
    if (!AppStores.isInitialized) {
      await AppStores.init();
    }

    final videoBox = AppStores.instance.videoStore.box<Video>();
    final detectionBox = AppStores.instance.detectionStore.box<Detection>();
    final videos = videoBox.getAll();
    final docsDir = await getApplicationDocumentsDirectory();

    final videoIdsToRemove = <int>[];
    final removedVideoNames = <String>{};

    for (final video in videos) {
      final file = File(
        p.join(
          docsDir.path,
          'camera_dir_${video.camera}',
          'videos',
          video.video,
        ),
      );
      if (!await file.exists()) {
        videoIdsToRemove.add(video.id);
        removedVideoNames.add(video.video);
      }
    }

    if (videoIdsToRemove.isNotEmpty) {
      videoBox.removeMany(videoIdsToRemove);
    }

    var removedDetectionRows = 0;
    if (removedVideoNames.isNotEmpty) {
      final detections = detectionBox.getAll();
      final detectionIdsToRemove =
          detections
              .where((d) => removedVideoNames.contains(d.videoFile))
              .map((d) => d.id)
              .toList();
      if (detectionIdsToRemove.isNotEmpty) {
        removedDetectionRows = detectionIdsToRemove.length;
        detectionBox.removeMany(detectionIdsToRemove);
      }
    }

    return StorageCleanupResult(
      bytesFreed: 0,
      deletedVideos: 0,
      deletedThumbnails: 0,
      deletedTempFiles: 0,
      removedVideoRows: videoIdsToRemove.length,
      removedDetectionRows: removedDetectionRows,
    );
  }

  static String formatBytes(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var suffixIndex = 0;
    while (value >= 1024 && suffixIndex < suffixes.length - 1) {
      value /= 1024;
      suffixIndex += 1;
    }
    final fractionDigits = value >= 100 || suffixIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fractionDigits)} ${suffixes[suffixIndex]}';
  }

  static String retentionLabel(int? days) {
    if (days == null) return 'Keep forever';
    return '$days days';
  }

  static Future<StorageCleanupResult> _deleteVideosWhere(
    bool Function(Video video) shouldDelete,
  ) async {
    if (!AppStores.isInitialized) {
      await AppStores.init();
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final videoBox = AppStores.instance.videoStore.box<Video>();
    final detectionBox = AppStores.instance.detectionStore.box<Detection>();
    final videos = videoBox.getAll();

    var bytesFreed = 0;
    var deletedVideos = 0;
    var deletedThumbnails = 0;
    final removedVideoIds = <int>[];
    final removedVideoNames = <String>{};
    final removedThumbnailNames = <String>{};

    for (final video in videos) {
      if (!shouldDelete(video)) continue;
      removedVideoIds.add(video.id);
      removedVideoNames.add(video.video);

      final videoFile = File(
        p.join(
          docsDir.path,
          'camera_dir_${video.camera}',
          'videos',
          video.video,
        ),
      );
      bytesFreed += await _safeDeleteFile(videoFile);
      deletedVideos += 1;

      final timestamp = _timestampTextFromVideoName(video.video);
      if (timestamp != null) {
        final thumbnailName = 'thumbnail_$timestamp.png';
        final thumbnailFile = File(
          p.join(
            docsDir.path,
            'camera_dir_${video.camera}',
            'videos',
            thumbnailName,
          ),
        );
        final thumbBytes = await _safeDeleteFile(thumbnailFile);
        if (thumbBytes > 0) {
          deletedThumbnails += 1;
          removedThumbnailNames.add(thumbnailName);
          bytesFreed += thumbBytes;
        }
      }
    }

    if (removedVideoIds.isNotEmpty) {
      videoBox.removeMany(removedVideoIds);
    }

    var removedDetectionRows = 0;
    if (removedVideoNames.isNotEmpty) {
      final detections = detectionBox.getAll();
      final detectionIdsToRemove =
          detections
              .where((d) => removedVideoNames.contains(d.videoFile))
              .map((d) => d.id)
              .toList();
      if (detectionIdsToRemove.isNotEmpty) {
        removedDetectionRows = detectionIdsToRemove.length;
        detectionBox.removeMany(detectionIdsToRemove);
      }
    }

    await _deleteEpochMarkersReferencing((name) {
      return removedVideoNames.contains(name) ||
          removedThumbnailNames.contains(name);
    });

    return StorageCleanupResult(
      bytesFreed: bytesFreed,
      deletedVideos: deletedVideos,
      deletedThumbnails: deletedThumbnails,
      deletedTempFiles: 0,
      removedVideoRows: removedVideoIds.length,
      removedDetectionRows: removedDetectionRows,
    );
  }

  static Future<void> _deleteEpochMarkersReferencing(
    bool Function(String markerPayload) shouldDelete,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    await for (final entity in docsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final basename = p.basename(entity.path);
      if (!basename.startsWith('.epoch_') || !basename.endsWith('.done')) {
        continue;
      }
      try {
        final content = (await entity.readAsString()).trim();
        if (content.isNotEmpty && shouldDelete(content)) {
          await entity.delete();
        }
      } catch (e) {
        Log.w('Failed to inspect epoch marker ${entity.path}: $e');
      }
    }
  }

  static DateTime? _timestampFromVideoName(String videoName) {
    final text = _timestampTextFromVideoName(videoName);
    if (text == null) return null;
    final value = int.tryParse(text);
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }

  static String? _timestampTextFromVideoName(String videoName) {
    if (!videoName.startsWith('video_') || !videoName.endsWith('.mp4')) {
      return null;
    }
    return videoName.substring(6, videoName.length - 4);
  }

  static Future<int> _safeDeleteFile(File file) async {
    try {
      if (!await file.exists()) return 0;
      final stat = await file.stat();
      final size = stat.size;
      await file.delete();
      return size;
    } catch (e) {
      Log.w('Failed to delete file ${file.path}: $e');
      return 0;
    }
  }

  static StorageCleanupResult _emptyCleanupResult() {
    return const StorageCleanupResult(
      bytesFreed: 0,
      deletedVideos: 0,
      deletedThumbnails: 0,
      deletedTempFiles: 0,
      removedVideoRows: 0,
      removedDetectionRows: 0,
    );
  }

  static StorageCleanupResult _mergeResults(
    StorageCleanupResult first,
    StorageCleanupResult second,
  ) {
    return StorageCleanupResult(
      bytesFreed: first.bytesFreed + second.bytesFreed,
      deletedVideos: first.deletedVideos + second.deletedVideos,
      deletedThumbnails: first.deletedThumbnails + second.deletedThumbnails,
      deletedTempFiles: first.deletedTempFiles + second.deletedTempFiles,
      removedVideoRows: first.removedVideoRows + second.removedVideoRows,
      removedDetectionRows:
          first.removedDetectionRows + second.removedDetectionRows,
    );
  }
}
