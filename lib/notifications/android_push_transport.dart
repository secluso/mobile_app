//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';

class AndroidPushTransport {
  static const fdroidUnifiedOnly = bool.fromEnvironment('SECLUSO_FDROID_BUILD');
  static const fcm = 'android';
  static const unified = 'android_unified';

  static String get defaultValue => fdroidUnifiedOnly ? unified : fcm;

  static String fromPrefs(SharedPreferences prefs) {
    if (fdroidUnifiedOnly) {
      return unified;
    }
    return prefs.getString(PrefKeys.androidPushPlatform) ?? defaultValue;
  }

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return fromPrefs(prefs);
  }

  static bool get allowsChoice => !fdroidUnifiedOnly;
  static bool isUnifiedValue(String value) => value == unified;
  static bool isUnifiedPrefs(SharedPreferences prefs) =>
      isUnifiedValue(fromPrefs(prefs));
}
