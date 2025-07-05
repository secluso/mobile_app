import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:privastead_flutter/objectbox.g.dart';
import 'package:privastead_flutter/utilities/logger.dart';

import 'package:privastead_flutter/routes/camera/view_video.dart';
import 'package:privastead_flutter/routes/camera/view_camera.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/main.dart';
import 'package:privastead_flutter/database/app_stores.dart';

final FlutterLocalNotificationsPlugin _notifs =
    FlutterLocalNotificationsPlugin();

// Initialization method
Future<void> initLocalNotifications() async {
  Log.d("Init local notifications called");
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
    onDidReceiveNotificationResponse: (resp) async {
      if (resp.payload != null) {
        Log.d("On video tap");
        Map<String, dynamic> callInfo = jsonDecode(resp.payload!);

        if (callInfo.containsKey("cameraName") &&
            callInfo.containsKey("timestamp")) {
          String cameraName = callInfo["cameraName"].toString();
          String timestamp = callInfo["timestamp"].toString();

          final box = AppStores.instance.videoStore.box<Video>();
          final videoQuery =
              box
                  .query(
                    Video_.camera
                        .equals(cameraName)
                        .and(Video_.video.contains(timestamp)),
                  )
                  .build();
          final foundVideo = videoQuery.findFirst();
          videoQuery.close();

          final navCtx = navigatorKey.currentContext;

          if (foundVideo == null) {
            Log.i("Not in database yet. Send to $cameraName");

            if (navCtx != null) {
              ScaffoldMessenger.of(navCtx).showSnackBar(
                const SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(
                    "Video from notification is being downloaded",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              );

              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => CameraViewPage(cameraName: cameraName),
                ),
              );
            }
          } else {
            Log.i("Found video. ${foundVideo.video}");

            if (navCtx != null) {
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder:
                      (_) => VideoViewPage(
                        cameraName: foundVideo.camera,
                        videoTitle: foundVideo.video,
                        visibleVideoTitle: repackageVideoTitle(
                          foundVideo.video,
                        ),
                        detections:
                            foundVideo.motion && foundVideo.received
                                ? ['Human']
                                : [],
                        canDownload: foundVideo.received,
                      ),
                ),
              );
            }
          }
        }
      }
    },
  );

  // Ask OS for notification permission
  // await _ensureNotificationPermissions();

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
    ledColor: const Color(0xFF00FF00),
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
  Log.d("Sent notification!");

  await _notifs.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique id
    cameraName, // title
    'Motion at $formatted', // body
    details,
    payload: jsonEncode({
      "cameraName": cameraName,
      "timestamp": timestamp,
    }), // deep-link payload
  );
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

Future<void> showHeartbeatNotification({
  required String cameraName,
  required String msg,
}) async {
  // Android
  final androidDetails = AndroidNotificationDetails(
    'repair_channel', // must match channel id below
    'Re-pair Events',
    channelDescription: 'Camera re-pair alerts',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    vibrationPattern: Int64List.fromList([500, 500, 500, 500, 500]),
    enableLights: true,
    color: const Color(0xFF00FF00),
    ledColor: const Color(0xFF00FF00),
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
  Log.d("Sent re-pair notification!");

  await _notifs.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique id
    cameraName, // title
    msg, // body
    details,
  );
}
