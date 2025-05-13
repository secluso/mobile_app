import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

final FlutterLocalNotificationsPlugin _notifs =
    FlutterLocalNotificationsPlugin();

// Initialization method
Future<void> initLocalNotifications() async {
  // basic engine bootstrap (no permissions yet)
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('ic_notification'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    ),
  );
  await _notifs.initialize(
    initSettings,
    // optional deep-link handler
    //onDidReceiveNotificationResponse: (resp) {
    //  final _cameraName = resp.payload; // open VideoList page, etc.
    // },
  );

  // Ask OS for notification permission
  await _ensureNotificationPermissions();

  // Create Android channel (no effect on iOS)
  if (Platform.isAndroid) await _ensureMotionChannelAndroid();
}

Future<void> showMotionNotification({
  required String cameraName,
  required String timestamp, // unix seconds
}) async {
  final formatted = _formatTimestamp(timestamp);

  // Android
  final androidDetails = AndroidNotificationDetails(
    'motion_channel', // must match channel id below
    'Motion Events',
    channelDescription: 'Camera motion alerts',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    vibrationPattern: Int64List.fromList([500, 500, 500, 500, 500]),
    enableLights: true,
    color: const Color(0xFF00FF00),
    ledOnMs: 2000,
    ledOffMs: 2000,
  );

  // iOS
  final iosDetails = const DarwinNotificationDetails(
    interruptionLevel: InterruptionLevel.timeSensitive,
    sound: 'default',
    badgeNumber: 1,
  );

  // Cross-platform wrapper
  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _notifs.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique id
    cameraName, // title
    'Motion at $formatted', // body
    details,
    payload: cameraName, // deep-link payload
  );
}

Future<void> _ensureNotificationPermissions() async {
  if (Platform.isAndroid) {
    final androidPlugin =
        _notifs
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    // Android 13+ runtime permission
    final granted = (await androidPlugin?.areNotificationsEnabled()) ?? true;
    if (!granted) await androidPlugin?.requestNotificationsPermission();
  } else if (Platform.isIOS) {
    await _notifs
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }
}

Future<void> _ensureMotionChannelAndroid() async {
  const channel = AndroidNotificationChannel(
    'motion_channel', // id
    'Motion Events', // visible name
    description: 'Camera motion alerts',
    importance: Importance.high,
  );

  await _notifs
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

String _formatTimestamp(String unixSeconds) {
  final secs = int.tryParse(unixSeconds) ?? 0;
  final date =
      DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
}
