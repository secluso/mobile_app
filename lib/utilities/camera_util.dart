import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:privastead_flutter/keys.dart';

Future<bool> addCamera(
  String cameraName,
  String ip,
  List<int> secret,
  bool standalone,
  String ssid,
  String password,
) async {
  if (!(await connect(cameraName))) {
    print("Connect = false");
    return false;
  }

  return await flutterAddCamera(
    cameraName: cameraName,
    ip: ip,
    secret: secret,
    standalone: standalone,
    ssid: ssid,
    password: password,
  );
}

Future<bool> connect(String cameraName) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool firstTimeConnectionDone =
      prefs.getBool("first_time_" + cameraName) ?? false;

  if (!firstTimeConnectionDone) {
    print("Connect core true");
    bool success = await connectCore(cameraName, true);
    return success;
  } else {
    print("Connect core false");
    bool success = await connectCore(cameraName, false);
    return success;
  }
}

Future<bool> connectCore(String cameraName, bool firstTime) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String serverIP =
      prefs.getString(PrefKeys.savedIp) ??
      "Error"; // TODO: Make this not a static field
  if (serverIP == "Error") {
    print("Error: Failed to retrieve server IP address");
    return false;
  }

  // TODO: How should we move our FCM token into production?
  var fcmToken = prefs.getString(PrefKeys.fcmToken) ?? "Error";
  if (fcmToken == "Error") {
    print("Error: Failed to retrieve FCM token");
    return false;
  }

  var userCredentialsString =
      prefs.getString(PrefKeys.serverPassword) ??
      "Error"; // If the password's set, we implicitly know the username is too (validity checks before setting either)
  if (userCredentialsString == "Error") {
    print("Error: Failed to retrieve user credentials");
    return false;
  }

  var filesDir =
      (await getApplicationDocumentsDirectory()).absolute.path +
      "/camera_dir_" +
      cameraName;

  print("Files Directory: $filesDir");

  // Create directory if it doesn't exist
  var dir = await Directory(filesDir);
  if (!(await dir.exists())) {
    try {
      await dir.create(recursive: true);
    } catch (e) {
      print("Error: Failed to create directory for files");
    }
  }

  print("Connect core: Proceeding to call rust initializeCamera method");

  return await initializeCamera(
    fileDir: filesDir,
    cameraName: cameraName,
    firstTime: firstTime,
  );
}
