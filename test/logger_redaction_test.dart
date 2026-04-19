//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:secluso_flutter/utilities/logger.dart';

void main() {
  test('redacts assignment-style secrets in copied logs', () {
    const input =
        '12:00:00.000 [E] main.dart:1:1 -> passphrase = camera-pass, token: abc123';

    final redacted = Log.redactSecretsForCopy(input);

    expect(
      redacted,
      '12:00:00.000 [E] main.dart:1:1 -> passphrase = SECRET HIDDEN, token: SECRET HIDDEN',
    );
  });

  test('redacts narrative token disclosures in copied logs', () {
    const input =
        '12:00:00.000 [D] firebase.dart:1:1 -> Set FCM token to xyz789';

    final redacted = Log.redactSecretsForCopy(input);

    expect(
      redacted,
      '12:00:00.000 [D] firebase.dart:1:1 -> Set FCM token to SECRET HIDDEN',
    );
  });

  test('preserves surrounding punctuation when redacting', () {
    const input =
        '12:00:00.000 [D] relay.dart:1:1 -> Updated APNs token (token=abc123)';

    final redacted = Log.redactSecretsForCopy(input);

    expect(
      redacted,
      '12:00:00.000 [D] relay.dart:1:1 -> Updated APNs token (token=SECRET HIDDEN)',
    );
  });

  test('leaves non-secret log text unchanged', () {
    const input =
        '12:00:00.000 [I] scheduler.dart:1:1 -> Network statuses: wifi = true, cell = false';

    final redacted = Log.redactSecretsForCopy(input);

    expect(redacted, input);
  });
}
