import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/src/rust/api.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:secluso_flutter/keys.dart';

Future<String> addCamera(
  String cameraName,
  String ip,
  List<int> secret,
  bool standalone,
  String ssid,
  String password,
  String pairingToken,
) async {
  Log.d("In addCamera");
  if (!(await initialize(cameraName))) {
    Log.e("Connect = false");
    return "Error";
  }

  final prefs = await SharedPreferences.getInstance();
  final credentialsFull = prefs.getString(PrefKeys.credentialsFull);

  if (credentialsFull == null) {
    Log.e("credentialsFull is null");
    return "Error";
  }

  Log.d("Calling flutter add camera");

  return await flutterAddCamera(
    cameraName: cameraName,
    ip: ip,
    secret: secret,
    standalone: standalone,
    ssid: ssid,
    password: password,
    pairingToken: pairingToken,
    credentialsFull: credentialsFull,
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
  //FIXME: do we still need these checks on serverAddr and user credentials?
  final String serverAddr =
      prefs.getString(PrefKeys.serverAddr) ??
      "Error"; // TODO: Make this not a static field
  if (serverAddr == "Error") {
    Log.e("Error: Failed to retrieve server address");
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
