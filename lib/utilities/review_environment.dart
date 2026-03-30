//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/ui/secluso_preview_assets.dart';

class ReviewRelayQrPayload {
  const ReviewRelayQrPayload({
    required this.relayId,
    required this.relayLabel,
    required this.relayAddress,
  });

  final String relayId;
  final String relayLabel;
  final String relayAddress;

  static ReviewRelayQrPayload? tryParseMap(Map<dynamic, dynamic> decoded) {
    final versionKey = decoded['v'];
    final relayId = decoded['rid'];
    final relayLabel = decoded['rl'];
    final relayAddress = decoded['sa'];
    if (versionKey is! String ||
        relayId is! String ||
        relayLabel is! String ||
        relayAddress is! String ||
        versionKey != Constants.reviewRelayQrCodeVersion) {
      return null;
    }
    if (relayId.trim().isEmpty ||
        relayLabel.trim().isEmpty ||
        relayAddress.trim().isEmpty) {
      return null;
    }
    return ReviewRelayQrPayload(
      relayId: relayId.trim(),
      relayLabel: relayLabel.trim(),
      relayAddress: relayAddress.trim(),
    );
  }
}

class ReviewCameraQrPayload {
  const ReviewCameraQrPayload({
    required this.cameraId,
    required this.cameraName,
    required this.profileId,
  });

  final String cameraId;
  final String cameraName;
  final String profileId;

  static ReviewCameraQrPayload? tryParseMap(Map<dynamic, dynamic> decoded) {
    final versionKey = decoded['v'];
    final cameraId = decoded['cid'];
    final cameraName = decoded['cn'];
    final profileId = decoded['profile'];
    if (versionKey is! String ||
        cameraId is! String ||
        cameraName is! String ||
        profileId is! String ||
        versionKey != Constants.reviewCameraQrCodeVersion) {
      return null;
    }
    if (cameraId.trim().isEmpty ||
        cameraName.trim().isEmpty ||
        profileId.trim().isEmpty) {
      return null;
    }
    return ReviewCameraQrPayload(
      cameraId: cameraId.trim(),
      cameraName: cameraName.trim(),
      profileId: profileId.trim(),
    );
  }
}

class ReviewClipFixture {
  const ReviewClipFixture({
    required this.videoFile,
    required this.previewAssetPath,
    required this.videoAssetPath,
    required this.detections,
    required this.motion,
    required this.duration,
    required this.timeLabel,
    required this.sectionLabel,
  });

  final String videoFile;
  final String previewAssetPath;
  final String? videoAssetPath;
  final Set<String> detections;
  final bool motion;
  final Duration duration;
  final String timeLabel;
  final String sectionLabel;

  Map<String, dynamic> toJson() => {
    'videoFile': videoFile,
    'previewAssetPath': previewAssetPath,
    'videoAssetPath': videoAssetPath,
    'detections': detections.toList(),
    'motion': motion,
    'durationMs': duration.inMilliseconds,
    'timeLabel': timeLabel,
    'sectionLabel': sectionLabel,
  };

  factory ReviewClipFixture.fromJson(Map<dynamic, dynamic> json) {
    return ReviewClipFixture(
      videoFile: (json['videoFile'] as String?) ?? '',
      previewAssetPath: (json['previewAssetPath'] as String?) ?? '',
      videoAssetPath: json['videoAssetPath'] as String?,
      detections:
          ((json['detections'] as List?) ?? const [])
              .whereType<String>()
              .map((entry) => entry.toLowerCase())
              .toSet(),
      motion: json['motion'] as bool? ?? true,
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      timeLabel: (json['timeLabel'] as String?) ?? '',
      sectionLabel: (json['sectionLabel'] as String?) ?? '',
    );
  }
}

class ReviewCameraFixture {
  const ReviewCameraFixture({
    required this.id,
    required this.name,
    required this.profileId,
    required this.livePreviewAssetPath,
    required this.livePreviewVideoAssetPath,
    required this.statusLabel,
    required this.recentActivityTitle,
    required this.recentActivityTimeLabel,
    required this.hasUnreadActivity,
    required this.clips,
  });

  final String id;
  final String name;
  final String profileId;
  final String livePreviewAssetPath;
  final String? livePreviewVideoAssetPath;
  final String statusLabel;
  final String recentActivityTitle;
  final String recentActivityTimeLabel;
  final bool hasUnreadActivity;
  final List<ReviewClipFixture> clips;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'profileId': profileId,
    'livePreviewAssetPath': livePreviewAssetPath,
    'livePreviewVideoAssetPath': livePreviewVideoAssetPath,
    'statusLabel': statusLabel,
    'recentActivityTitle': recentActivityTitle,
    'recentActivityTimeLabel': recentActivityTimeLabel,
    'hasUnreadActivity': hasUnreadActivity,
    'clips': clips.map((clip) => clip.toJson()).toList(),
  };

  factory ReviewCameraFixture.fromJson(Map<dynamic, dynamic> json) {
    return ReviewCameraFixture(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      profileId: (json['profileId'] as String?) ?? 'front-door',
      livePreviewAssetPath: (json['livePreviewAssetPath'] as String?) ?? '',
      livePreviewVideoAssetPath:
          json['livePreviewVideoAssetPath'] as String?,
      statusLabel: (json['statusLabel'] as String?) ?? 'Quiet',
      recentActivityTitle:
          (json['recentActivityTitle'] as String?) ?? 'Person detected',
      recentActivityTimeLabel:
          (json['recentActivityTimeLabel'] as String?) ?? '2m ago',
      hasUnreadActivity: json['hasUnreadActivity'] as bool? ?? true,
      clips: ((json['clips'] as List?) ?? const [])
          .whereType<Map>()
          .map(ReviewClipFixture.fromJson)
          .where((clip) => clip.videoFile.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ReviewEnvironmentSession {
  const ReviewEnvironmentSession({
    required this.relayId,
    required this.relayLabel,
    required this.relayAddress,
    required this.cameras,
  });

  final String relayId;
  final String relayLabel;
  final String relayAddress;
  final List<ReviewCameraFixture> cameras;

  List<String> get cameraNames =>
      cameras.map((camera) => camera.name).toList(growable: false);

  ReviewCameraFixture? cameraByName(String name) {
    for (final camera in cameras) {
      if (camera.name == name) {
        return camera;
      }
    }
    return null;
  }

  ReviewEnvironmentSession copyWith({
    String? relayId,
    String? relayLabel,
    String? relayAddress,
    List<ReviewCameraFixture>? cameras,
  }) {
    return ReviewEnvironmentSession(
      relayId: relayId ?? this.relayId,
      relayLabel: relayLabel ?? this.relayLabel,
      relayAddress: relayAddress ?? this.relayAddress,
      cameras: cameras ?? this.cameras,
    );
  }

  Map<String, dynamic> toJson() => {
    'relayId': relayId,
    'relayLabel': relayLabel,
    'relayAddress': relayAddress,
    'cameras': cameras.map((camera) => camera.toJson()).toList(),
  };

  factory ReviewEnvironmentSession.fromJson(Map<dynamic, dynamic> json) {
    return ReviewEnvironmentSession(
      relayId: (json['relayId'] as String?) ?? '',
      relayLabel: (json['relayLabel'] as String?) ?? '',
      relayAddress: (json['relayAddress'] as String?) ?? '',
      cameras: ((json['cameras'] as List?) ?? const [])
          .whereType<Map>()
          .map(ReviewCameraFixture.fromJson)
          .where((camera) => camera.id.isNotEmpty && camera.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ReviewEnvironment extends ChangeNotifier {
  ReviewEnvironment._();

  static final ReviewEnvironment instance = ReviewEnvironment._();

  ReviewEnvironmentSession? _session;
  bool _loaded = false;

  ReviewEnvironmentSession? get session => _session;
  bool get isActive => _session != null;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PrefKeys.reviewEnvironmentJson);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final loadedSession = ReviewEnvironmentSession.fromJson(decoded);
          if (loadedSession.relayId.isNotEmpty &&
              loadedSession.relayLabel.isNotEmpty &&
              loadedSession.relayAddress.isNotEmpty) {
            _session = loadedSession;
          }
        }
      } catch (_) {
        _session = null;
      }
    }
    _loaded = true;
  }

  Future<void> activateRelay(ReviewRelayQrPayload payload) async {
    await ensureLoaded();
    final existing = _session;
    final preservedCameras =
        existing != null && existing.relayId == payload.relayId
            ? existing.cameras
            : const <ReviewCameraFixture>[];
    _session = ReviewEnvironmentSession(
      relayId: payload.relayId,
      relayLabel: payload.relayLabel,
      relayAddress: payload.relayAddress,
      cameras: preservedCameras,
    );
    await _persist();
    notifyListeners();
  }

  Future<bool> addCamera(ReviewCameraQrPayload payload) async {
    await ensureLoaded();
    final existing = _session;
    if (existing == null) {
      return false;
    }
    final alreadyPresent = existing.cameras.any(
      (camera) =>
          camera.id == payload.cameraId || camera.name == payload.cameraName,
    );
    if (alreadyPresent) {
      return false;
    }
    final fixture = _fixtureForPayload(payload);
    if (fixture == null) {
      return false;
    }
    _session = existing.copyWith(cameras: [...existing.cameras, fixture]);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> removeCameraByName(String cameraName) async {
    await ensureLoaded();
    final existing = _session;
    if (existing == null) {
      return;
    }
    final remaining = existing.cameras
        .where((camera) => camera.name != cameraName)
        .toList(growable: false);
    if (remaining.length == existing.cameras.length) {
      return;
    }
    _session = existing.copyWith(cameras: remaining);
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    await ensureLoaded();
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.reviewEnvironmentJson);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final activeSession = _session;
    if (activeSession == null) {
      await prefs.remove(PrefKeys.reviewEnvironmentJson);
      return;
    }
    await prefs.setString(
      PrefKeys.reviewEnvironmentJson,
      jsonEncode(activeSession.toJson()),
    );
  }

  ReviewCameraFixture? _fixtureForPayload(ReviewCameraQrPayload payload) {
    final normalizedProfile = payload.profileId.trim().toLowerCase().replaceAll(
      '_',
      '-',
    );
    switch (normalizedProfile) {
      case 'front-door':
      case 'frontdoor':
      default:
        return ReviewCameraFixture(
          id: payload.cameraId,
          name: payload.cameraName,
          profileId: 'front-door',
          livePreviewAssetPath: SeclusoPreviewAssets.designFrontDoor,
          livePreviewVideoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
          statusLabel: 'Person · 2m',
          recentActivityTitle: 'Person detected',
          recentActivityTimeLabel: '2m ago',
          hasUnreadActivity: true,
          clips: const [
            ReviewClipFixture(
              videoFile: 'video_1774540440.mp4',
              previewAssetPath: SeclusoPreviewAssets.hallwayEvent,
              videoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
              detections: {'human'},
              motion: true,
              duration: Duration(seconds: 16),
              timeLabel: '2:34 PM',
              sectionLabel: 'TODAY',
            ),
            ReviewClipFixture(
              videoFile: 'video_1774539600.mp4',
              previewAssetPath: SeclusoPreviewAssets.foyerEvent,
              videoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
              detections: {},
              motion: true,
              duration: Duration(seconds: 16),
              timeLabel: '2:20 PM',
              sectionLabel: 'TODAY',
            ),
            ReviewClipFixture(
              videoFile: 'video_1774261920.mp4',
              previewAssetPath: SeclusoPreviewAssets.deliveryNookEvent,
              videoAssetPath: SeclusoPreviewAssets.reviewFrontDoorClip,
              detections: {'human'},
              motion: true,
              duration: Duration(seconds: 16),
              timeLabel: 'Mon 9:12 AM',
              sectionLabel: 'EARLIER THIS WEEK',
            ),
          ],
        );
    }
  }
}
