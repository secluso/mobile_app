import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:secluso_flutter/notifications/firebase_options.dart';

class FirebaseInit {
  static Completer<FirebaseApp>? _c;

  static Future<FirebaseApp> ensure() {
    if (_c != null) return _c!.future;
    _c = Completer<FirebaseApp>();
    () async {
      try {
        // If already initialized natively or earlier in Dart, this succeeds.
        FirebaseApp app;
        try {
          app = Firebase.app();
        } on FirebaseException catch (e) {
          if (e.code == 'no-app') {
            app = await Firebase.initializeApp(
              name:
                  "Secluso", // Note: Without a name, this is [DEFAULT] which conflicts with other apps (like the old app we had with a different name)
              options: DefaultFirebaseOptions.currentPlatform,
            );
          } else {
            rethrow;
          }
        }
        _c!.complete(app);
      } catch (e, st) {
        _c!.completeError(e, st);
      }
    }();
    return _c!.future;
  }
}
