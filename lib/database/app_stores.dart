//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:secluso_flutter/objectbox.g.dart';
import 'entities.dart';

/// Holds box ObjectBox stores (camera + video) as a single global singleton.
class AppStores {
  static final AppStores _singleton = AppStores._internal();
  AppStores._internal();

  static bool _initialized = false;
  static Future<AppStores>? _opening;
  static bool _closing = false;

  /// Initialization ran once in runApp
  static Future<AppStores> init() async {
    if (_initialized) return _singleton; // already ready
    if (_opening != null) return _opening!;
    _opening = _initInternal().whenComplete(() => _opening = null);
   return _opening!;
  }

  static bool get isInitialized => _initialized;

  static Future<AppStores> _initInternal() async {
    final docsDir = await getApplicationDocumentsDirectory();
    _singleton._cameraStore = await openStore(
      directory: p.join(docsDir.path, 'camera-db'),
    );
    _singleton._videoStore = await openStore(
      directory: p.join(docsDir.path, 'video-db'),
    );
    _singleton._detectionStore = await openStore(
      directory: p.join(docsDir.path, 'detection-db'),
    );

    _initialized = true;
    return _singleton;
  }

  static AppStores get instance {
    if (!_initialized) {
      throw StateError('AppStores.init() MUST be awaited before use.');
    }
    return _singleton;
  }

  // Actual stores
  late final Store _cameraStore;
  late final Store _videoStore;
  late final Store _detectionStore;

  Store get cameraStore => _cameraStore;
  Store get videoStore => _videoStore;
  Store get detectionStore => _detectionStore;

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      // These are sync methods, but wrap in try/finally so all close even if one throws.
      _cameraStore.close();
      _videoStore.close();
      _detectionStore.close();
      _initialized = false;
    } finally {
      _closing = false;
    }
  }
}
