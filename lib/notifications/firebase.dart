import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:privastead_flutter/notifications/notifications.dart';
import 'package:privastead_flutter/notifications/scheduler.dart';
import 'package:privastead_flutter/routes/camera/new/proprietary_camera_waiting.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:privastead_flutter/utilities/logger.dart';
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
    Log.init();
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
    Log.d("Initializing PushNotificationService");

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
      Log.d('onMessage');
      _handleMessage(msg);
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleTapFromTray);
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateToken);

    await initLocalNotifications();

    if (Platform.isAndroid ||
        (Platform.isIOS &&
            await FirebaseMessaging.instance.getAPNSToken() != null)) {
      final tok = await FirebaseMessaging.instance.getToken();
      Log.d("Set FCM token to $tok");
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
      Log.d("Attempting to capture token $android");
      if (Platform.isAndroid ||
          (Platform.isIOS &&
              await FirebaseMessaging.instance.getAPNSToken() != null)) {
        Log.d("Entered capturing area");

        final tok = await FirebaseMessaging.instance.getToken();
        Log.d("Set FCM token to $tok");
        if (tok != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefKeys.fcmToken, tok);
          token = tok;
          needUpdate = true;
        }
      }
    }

    if (credentials.isEmpty || token.isEmpty || (!force && !needUpdate)) {
      Log.d("Skipping update");
      return;
    }

    final result = await HttpClientService.instance.uploadFcmToken(token);
    if (result.isSuccess) {
      prefs.setBool(PrefKeys.needUpdateFcmToken, false);
      Log.d('[FCM] token re‑uploaded');
    } else {
      Log.d('[FCM] token upload failed');
    }
  }

  Future<void> _handleMessage(RemoteMessage msg) => _process(msg.data);
  void _handleTapFromTray(RemoteMessage msg) {}

  // Core notification processing method
  Future<void> _process(Map<String, dynamic> data) async {
    Log.d("Core notification processing method entered");
    final encoded = data['body'];
    if (encoded == null) return;

    Log.d("Got a message");

    final prefs = await SharedPreferences.getInstance();
    //  await WakelockPlus.enable(); // TODO: Make this optional depending on if it's called from background processing

    try {
      final Uint8List bytes = base64Decode(encoded);
      final List<String> cameraSet =
          prefs.getStringList(PrefKeys.cameraSet) ?? [];

      // If we have a waiting FCM camera within the last minute, we allow it to pass through.
      if (prefs.containsKey(PrefKeys.waitingAdditionalCamera) &&
          !cameraSet.contains(
            prefs.getString(PrefKeys.waitingAdditionalCamera),
          )) {
        var time = prefs.getInt(PrefKeys.waitingAdditionalCameraTime);
        var currentTime = DateTime.now().millisecondsSinceEpoch;
        if (time != null) {
          var diff = time - currentTime;
          if (diff <= 60000) {
            cameraSet.add(prefs.getString(PrefKeys.waitingAdditionalCamera)!);
          }
        }
      }

      Log.d('Pre-existing camera set: $cameraSet');

      final bool needNotification =
          prefs.getBool('saved_need_notification_state') ?? true;

      // TODO: what happens if we have an invalid name?
      for (final cameraName in cameraSet) {
        Log.d("Starting to iterate $cameraName");
        final String response = await decryptFcmMessage(
          cameraName: cameraName,
          data: bytes,
        );

        Log.d("Decoded response is: $response");
        try {
          final decodedJson = jsonDecode(response) as Map<String, dynamic>;
          if (decodedJson.containsKey("type")) {
            var type = decodedJson['type'];
            if (type == "wifi_success") {
              Log.d(
                "Got successful wifi FCM notification for camera $cameraName, $response",
              );

              var timestamp = decodedJson['timestamp'];
              var date = new DateTime.fromMillisecondsSinceEpoch(timestamp);

              ProprietaryCameraWaitingDialog.completePairingForCamera(
                cameraName,
                date,
              );
            } else {
              Log.e("Error: Unknown JSON message type: $type");
            }
          } else {
            Log.e("Error: JSON FCM message didn't contain type key");
          }
        } catch (_) {
          if (response == 'Download') {
            Log.d("Downloading video");
            final bool useMobile = prefs.getBool('use_mobile_state') ?? false;

            final status = await Connectivity().checkConnectivity();
            final bool isMetered = status == ConnectivityResult.mobile;
            final bool isRestricted = false;

            if (!isMetered || (useMobile && !isRestricted)) {
              DownloadScheduler.scheduleVideoDownload(
                cameraName,
              ); // Don't await, as the lock may freeze this up
            }
          } else if (response != 'Error!' && response != 'None') {
            Log.d("Showing motion notification");
            //TODO: Figure out if (needNotification) {
            showMotionNotification(cameraName: cameraName, timestamp: response);

            // TODO: I removed the pending to repository addition for Android because it's not possible to init ObjectBox in the background handler (as Android requires). Find alternate solution maybe. Not sure this is needed anymore (as we don't want to show users pending videos in cases of failure)
            if (Platform.isIOS) {
              await addPendingToRepository(cameraName, response);
            }
          }
        }
      }
    } finally {
      Log.d("After processing");
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
