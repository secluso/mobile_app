//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

class VersionGateInfo {
  const VersionGateInfo({
    required this.title,
    required this.message,
    required this.serverVersion,
    required this.clientVersion,
  });

  final String title;
  final String message;
  final String serverVersion;
  final String clientVersion;

  factory VersionGateInfo.mismatch({
    required String serverVersion,
    required String clientVersion,
  }) {
    return VersionGateInfo(
      title: 'Update required',
      message: 'Server and app versions do not match.',
      serverVersion: serverVersion,
      clientVersion: clientVersion,
    );
  }
}

class VersionGate {
  static final ValueNotifier<VersionGateInfo?> notifier =
      ValueNotifier<VersionGateInfo?>(null);

  static bool get isBlocked => notifier.value != null;

  static void block(VersionGateInfo info) {
    notifier.value = info;
  }

  static void clear() {
    notifier.value = null;
  }
}
