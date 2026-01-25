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
  //TODO: Incorporate a secondary check that will incorporate each camera connected version. If a camera isn't updated,
  // then it shouldn't be accessible from the app for new *decryptions*. We could still download encrypted bin files I suppose,
  // but we can't decrypt them without ensuring there aren't new standards in place. So, we need to somehow version those,
  // delegate so that we notify the user that the camera isn't up-to-date (through push and through an in-app block), and then block the decryptions of those files until the
  // correct app version is in place.

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
