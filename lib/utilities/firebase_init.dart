import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:platform/platform.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/logger.dart';

class FirebaseInit {
  static Completer<FirebaseApp>? _c;
  static bool _initialized = false;
  static FirebaseApp? _app;

  static bool get isInitialized => _initialized;
  static FirebaseApp? get app => _app;

  static Future<FirebaseApp> ensure(FcmConfig fcmConfig) {
    if (_c != null) return _c!.future;
    _c = Completer<FirebaseApp>();
    () async {
      try {
        Log.init();
        // If already initialized earlier in Dart, this succeeds.
        FirebaseApp app;
        try {
          app = Firebase.app();
        } on FirebaseException catch (e) {
          Log.d("Working on ensuring initialization for firebase");
          FirebaseOptions android = FirebaseOptions(
            apiKey: fcmConfig.api_key_android,
            appId: fcmConfig.app_id_android,
            messagingSenderId: fcmConfig.messaging_sender_id,
            projectId: fcmConfig.project_id,
            storageBucket: fcmConfig.storage_bucket,
          );

          FirebaseOptions ios = FirebaseOptions(
            apiKey: fcmConfig.api_key_ios,
            appId: fcmConfig.app_id_ios,
            messagingSenderId: fcmConfig.messaging_sender_id,
            projectId: fcmConfig.project_id,
            storageBucket: fcmConfig.storage_bucket,
            iosBundleId: fcmConfig.bundle_id,
          );

          // assign based on OS (or error if not found)
          FirebaseOptions options;
          if (const LocalPlatform().isAndroid) {
            options = android;
          } else if (const LocalPlatform().isIOS) {
            options = ios;
          } else {
            throw UnsupportedError(
              "Firebase is only supported on Android and iOS",
            );
          }

          if (e.code == 'no-app') {
            app = await Firebase.initializeApp(
              options: options,
            );
          } else {
            rethrow;
          }
        }
        _app = app;
        _initialized = true;
        _c!.complete(app);
      } catch (e, st) {
        _c!.completeError(e, st);
      }
    }();
    return _c!.future;
  }
}
