//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:uuid/uuid.dart';

final Uuid _uuid = Uuid();

String? deriveHubIdFromServerUsername(String? serverUsername) {
  final normalized = serverUsername?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return _uuid.v5(Uuid.NAMESPACE_URL, 'secluso-hub:$normalized');
}
