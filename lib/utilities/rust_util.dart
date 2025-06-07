import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:privastead_flutter/keys.dart';

Future<bool> addCamera(
  String cameraName,
  String ip,
  List<int> secret,
  bool standalone,
  String ssid,
  String password,
  String pairingToken,
) async {
  if (!(await initialize(cameraName))) {
    Log.d("Connect = false");
    return false;
  }

  return await flutterAddCamera(
    cameraName: cameraName,
    ip: ip,
    secret: secret,
    standalone: standalone,
    ssid: ssid,
    password: password,
    pairingToken: pairingToken,
  );
}

Future<bool> initialize(String cameraName) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool firstTimeConnectionDone =
      prefs.getBool("first_time_" + cameraName) ?? false;

  Log.d("First time connection done: $firstTimeConnectionDone");

  bool success = await initializeCore(cameraName, !firstTimeConnectionDone);
  return success;
}

Future<bool> initializeCore(String cameraName, bool firstTime) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String serverIP =
      prefs.getString(PrefKeys.savedIp) ??
      "Error"; // TODO: Make this not a static field
  if (serverIP == "Error") {
    Log.e("Error: Failed to retrieve server IP address");
    return false;
  }

  // TODO: How should we move our FCM token into production?
  var fcmToken = prefs.getString(PrefKeys.fcmToken) ?? "Error";
  if (fcmToken == "Error") {
    Log.e("Error: Failed to retrieve FCM token");
    return false;
  }

  var userCredentialsString =
      prefs.getString(PrefKeys.serverPassword) ??
      "Error"; // If the password's set, we implicitly know the username is too (validity checks before setting either)
  if (userCredentialsString == "Error") {
    Log.e("Error: Failed to retrieve user credentials");
    return false;
  }

  var filesDir =
      (await getApplicationDocumentsDirectory()).absolute.path +
      "/camera_dir_" +
      cameraName;

  // Create directory if it doesn't exist
  var dir = await Directory(filesDir);
  if (!(await dir.exists())) {
    try {
      await dir.create(recursive: true);
    } catch (e) {
      Log.e("Error: Failed to create directory for files");
    }
  }

  Log.d("Proceeding to call rust initializeCamera method");

  return await initializeCamera(
    fileDir: filesDir,
    cameraName: cameraName,
    firstTime: firstTime,
  );
}