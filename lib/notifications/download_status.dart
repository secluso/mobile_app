//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';

/// Tracks which cameras are actively downloading in a way that survives
/// background work and isolate swaps. The S.O.T. is a prefs-backed
/// set so background tasks can update it, while the in-memory cache plus
/// active notifier lets the UI make reactions without needing to be re-reading prefs
///  on every frame.
class DownloadStatus {
  static final ValueNotifier<int> active = ValueNotifier<int>(0);
  static final Set<String> _activeCameras = <String>{};

  static bool isActiveInMemory(String cameraName) {
    return _activeCameras.contains(cameraName);
  }

  static Future<void> markActive(String cameraName, bool isActive) async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        (prefs.getStringList(PrefKeys.downloadActiveCameras) ?? <String>[])
            .toSet();

    final changed =
        isActive ? stored.add(cameraName) : stored.remove(cameraName);
    if (changed) {
      await prefs.setStringList(
        PrefKeys.downloadActiveCameras,
        stored.toList(),
      );
    }

    _updateInMemory(stored);
  }

  static Future<void> syncFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        (prefs.getStringList(PrefKeys.downloadActiveCameras) ?? <String>[])
            .toSet();
    _updateInMemory(stored);
  }

  static void _updateInMemory(Set<String> updated) {
    if (setEquals(_activeCameras, updated)) {
      return;
    }

    _activeCameras
      ..clear()
      ..addAll(updated);
    active.value++;
  }
}
