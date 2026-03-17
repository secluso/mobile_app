//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VideoThumbnailFallback {
  VideoThumbnailFallback._();

  static const MethodChannel _channel = MethodChannel('secluso.com/thumbnail');
  static final Map<String, Future<Uint8List?>> _pending = {};

  static Future<Uint8List?> generate(
    String videoPath, {
    bool fullSize = false,
  }) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Future.value(null);
    }

    final cacheKey = '$videoPath::$fullSize';
    final existing = _pending[cacheKey];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      try {
        final bytes = await _channel.invokeMethod<Uint8List>(
          'generateThumbnail',
          {'path': videoPath, 'fullSize': fullSize},
        );
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _pending.remove(cacheKey);
      }
    }();

    _pending[cacheKey] = future;
    return future;
  }
}
