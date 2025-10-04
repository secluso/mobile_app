//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:secluso_flutter/src/rust/api.dart' show shutdownApp;
import 'package:secluso_flutter/src/rust/frb_generated.dart' show RustLib;

class RustLibGuard {
  static Future<void>? _opening;
  static bool _initialized = false;

  static Future<void> initOnce() {
    if (_initialized) return Future.value();
    if (_opening != null) return _opening!;
    _opening = _init().whenComplete(() => _opening = null);
    return _opening!;
  }

  static Future<void> _init() async {
    await RustLib.init();
    _initialized = true;
  }

  static Future<void> shutdownOnce() async {
    if (!_initialized) return;
    _initialized = false;
    try { await shutdownApp(); } catch (_) {}
  }

  static bool get isInitialized => _initialized;
}