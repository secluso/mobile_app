//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerBundledFontLicenses() {
  _registerBundledFontLicense(
    packageName: 'Inter',
    assetPath: 'assets/licenses/fonts/Inter-LICENSE.txt',
  );
  _registerBundledFontLicense(
    packageName: 'Playfair Display',
    assetPath: 'assets/licenses/fonts/PlayfairDisplay-LICENSE.txt',
  );
  _registerBundledFontLicense(
    packageName: 'Roboto Mono',
    assetPath: 'assets/licenses/fonts/RobotoMono-LICENSE.txt',
  );
}

void _registerBundledFontLicense({
  required String packageName,
  required String assetPath,
}) {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(assetPath);
    yield LicenseEntryWithLineBreaks(<String>[packageName], text);
  });
}
