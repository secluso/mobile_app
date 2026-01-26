//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:secluso_flutter/utilities/logger.dart';

Future<void> requestNotificationsAfterFirstCameraAdd() async {
  final prefs = await SharedPreferences.getInstance();
  final notificationsRequested =
      prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
  if (!notificationsRequested) {
    return;
  }

  final status = await Permission.notification.status;
  final now = DateTime.now().millisecondsSinceEpoch;

  if (status.isDenied || status.isRestricted) {
    Log.d("Requesting notifications after first camera add");
    await prefs.setInt(PrefKeys.lastNotificationCheck, now);
    final result = await Permission.notification.request();
    if (result.isGranted) {
      if (!FirebaseInit.isInitialized) {
        Log.d("Skipping FCM permission request; Firebase not initialized");
      } else {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      PushNotificationService.tryUploadIfNeeded(true);
    }
    return;
  }

  if (status.isGranted) {
    await prefs.setInt(PrefKeys.lastNotificationCheck, now);
    PushNotificationService.tryUploadIfNeeded(true);
  }
}
