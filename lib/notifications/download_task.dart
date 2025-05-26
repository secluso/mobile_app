import 'package:privastead_flutter/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:privastead_flutter/objectbox.g.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/routes/app_drawer.dart';
import 'package:privastead_flutter/src/rust/frb_generated.dart';

// We have another instance of this due to Android requiring another RustLib for our DownloadTasks. This isn't necessary for iOS. We can only have one instance per process, thus needing this.
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

Future<bool> doWork(String cameraName) async {
  print("DownloadTask: Starting to work");

  // TODO: Should we wait for downloadingMotionVideos to be false before continuing? Is this meant to be a spinlock?
  var prefs = await SharedPreferences.getInstance();
  await prefs.setBool(PrefKeys.downloadingMotionVideos, true);

  await RustBridgeHelper.ensureInitialized();

  bool result = await retrieveVideos(cameraName);

  await prefs.setBool(PrefKeys.downloadingMotionVideos, false);

  return result;
}

//TODO: What if we miss a notification and don't get one for a long time? Should we occasionally query? What about if the user is in the app without any notifications?

Future<bool> retrieveVideos(String cameraName) async {
  var sharedPref = await SharedPreferences.getInstance();
  var epoch = sharedPref.getInt("epoch$cameraName") ?? 2;

  var successes = 0;

  while (true) {
    print(
      "Trying to download video for epoch $epoch with $cameraName and encVideo$epoch",
    );
    var result = await HttpClientService.instance.downloadVideo(
      cameraName: cameraName,
      epoch: epoch,
      fileName: "encVideo$epoch",
    );

    if (result.isSuccess) {
      print("Success!");
      var file = result.value!;
      print(file);
      print(file.path);
      var decFileName = await decryptVideo(
        cameraName: cameraName,
        encFilename: file.path,
      );
      print("Dec file name = $decFileName");

      if (decFileName != "Error") {
        await file
            .delete(); // TODO: Should we delete it if there's an error..? If we do, we need to skip an epoch (which would require returning true or something custom perhaps)

        final box = AppStores.instance.videoStore.box<Video>();

        // Build a query matching the camera and file name.
        final query =
            box
                .query(
                  Video_.camera.equals(cameraName) &
                      Video_.video.equals(decFileName) &
                      Video_.received.equals(false),
                )
                .build();

        final video = query.findFirst();
        query.close();

        print("Received 100%");

        if (video != null) {
          video.received = true;
          box.put(video); // ObjectBox updates since id is preserved
          successes++;
        } else {
          // We don't have an existing video for some reason... must've lost the FCM notification and we recovered it. Create the new video entity now
          var video = Video(
            cameraName,
            decFileName,
            true,
            true,
          ); //both received & motion (true, true)
          box.put(video);
          successes++;
        }

        camerasPageKey.currentState?.invalidateThumbnail(cameraName);
        sharedPref.setInt("epoch$cameraName", epoch + 1);
      }

      epoch += 1;
    } else {
      print("Failed here");
      // We keep trying until hitting an error. Allows us to catch up on epochs.
      break;
    }
  }

  if (successes >= 1) return true;
  return false;
}
