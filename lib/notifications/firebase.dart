import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:privastead_flutter/notifications/notifications.dart';
import 'package:privastead_flutter/notifications/scheduler.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../keys.dart';
//TODO: import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import '../utilities/result.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:privastead_flutter/src/rust/frb_generated.dart';
import 'dart:io' show Platform;

class TaskNames {
  static String downloadAndroid(String cam) => 'DownloadTask_$cam';
}

class RustBridgeHelper {
  static bool _initialized = false;

  static Future<void>? _initFuture;

  /// Call this to avoid double-initialize in Android in the entry-point
  static Future<void> ensureInitialized() {
    if (_initialized) {
      return Future.value();
    }

    _initFuture ??= _doInit();
    return _initFuture!;
  }

  static Future<void> _doInit() async {
    await RustLib.init();
    _initialized = true;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Re-init Firebase
  await Firebase.initializeApp();

  if (Platform.isAndroid) {
    await RustBridgeHelper.ensureInitialized();
  }

  await PushNotificationService.instance._process(message.data);
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _notifReady = false;

  Future<void> init() async {
    print("Initializing PushNotificationService");

    // Local notifications (heads‑up for motion + download complete)
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (resp) {
        // TODO: navigate to video list page using resp.payload
      },
    );
    _notifReady = true;

    // TODO: Does this clash with our "initLocalNotifications"?
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    //FCM streams
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      print('onMessage');
      _handleMessage(msg);
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleTapFromTray);
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateToken);

    await initLocalNotifications();

    if (Platform.isAndroid ||
        (Platform.isIOS &&
            await FirebaseMessaging.instance.getAPNSToken() != null)) {
      final tok = await FirebaseMessaging.instance.getToken();
      print("Set FCM token to $tok");
      if (tok != null) await _updateToken(tok);
    }
  }

  static Future<void> tryUploadIfNeeded(bool force) async {
    final prefs = await SharedPreferences.getInstance();
    var needUpdate = prefs.getBool(PrefKeys.needUpdateFcmToken) ?? false;
    var token = prefs.getString(PrefKeys.fcmToken) ?? '';
    final credentials = prefs.getString(PrefKeys.serverUsername) ?? '';

    if (token.isEmpty) {
      var android = Platform.isAndroid;
      print("Attempting to capture token $android");
      if (Platform.isAndroid ||
          (Platform.isIOS &&
              await FirebaseMessaging.instance.getAPNSToken() != null)) {
        print("Entered capturing area");

        final tok = await FirebaseMessaging.instance.getToken();
        print("Set FCM token to $tok");
        if (tok != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefKeys.fcmToken, tok);
          token = tok;
          needUpdate = true;
        }
      }
    }

    if (credentials.isEmpty || token.isEmpty || (!force && !needUpdate)) {
      print("Skipping update");
      return;
    }

    final result = await HttpClientService.instance.uploadFcmToken(token);
    if (result.isSuccess) {
      prefs.setBool(PrefKeys.needUpdateFcmToken, false);
      debugPrint('[FCM] token re‑uploaded');
    } else {
      debugPrint('[FCM] token upload failed');
    }
  }

  Future<void> _handleMessage(RemoteMessage msg) => _process(msg.data);
  void _handleTapFromTray(RemoteMessage msg) {}

  // Core notification processing method
  Future<void> _process(Map<String, dynamic> data) async {
    print("Before!");
    final encoded = data['body'];
    if (encoded == null) return;

    print("Got a message");

    final prefs = await SharedPreferences.getInstance();
    //  await WakelockPlus.enable(); // TODO: Make this optional depending on if it's called from background processing

    try {
      print("ATP - 1");
      final Uint8List bytes = base64Decode(encoded);
      print(bytes);
      final List<String> cameraSet =
          prefs.getStringList(PrefKeys.cameraSet) ?? const [];
      print(cameraSet);

      final bool needNotification =
          prefs.getBool('saved_need_notification_state') ?? true;

      for (final cameraName in cameraSet) {
        print("Starting to iterate $cameraName");
        final String response = await decryptFcmTimestamp(
          cameraName: cameraName,
          data: bytes,
        );

        print("Response is $response");

        if (response == 'Download') {
          final bool useMobile = prefs.getBool('use_mobile_state') ?? false;

          final status = await Connectivity().checkConnectivity();
          final bool isMetered = status == ConnectivityResult.mobile;
          final bool isRestricted = false;

          if (!isMetered || (useMobile && !isRestricted)) {
            await DownloadScheduler.scheduleVideoDownload(cameraName);
          }
        } else if (response != 'Error' && response != 'None') {
          //TODO: Figure out if (needNotification) {
          showMotionNotification(cameraName: cameraName, timestamp: response);

          // TODO: I removed the pending to repository addition for Android because it's not possible to init ObjectBox in the background handler (as Android requires). Find alternate solution maybe. Not sure this is needed anymore (as we don't want to show users pending videos in cases of failure)
          if (Platform.isIOS) {
            await addPendingToRepository(cameraName, response);
          }
        }
      }
    } finally {
      print("After processing");
      // await WakelockPlus.disable(); TODO: Fix above wakelock depending on foreground or not
    }
  }

  Future<void> addPendingToRepository(
    String cameraName,
    String timestamp,
  ) async {
    final box = AppStores.instance.videoStore.box<Video>();

    var videoName = "video_" + timestamp + ".mp4";
    var video = Video(cameraName, videoName, false, true);
    box.put(video);
  }

  // TODO: Consider combining this with _tryUploadIfNeeded... although this mainly functions as a callback
  Future<void> _updateToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.fcmToken, token);

    Result<void> result = await HttpClientService.instance.uploadFcmToken(
      token,
    );

    await prefs.setBool(PrefKeys.needUpdateFcmToken, result.isFailure);
  }
}
