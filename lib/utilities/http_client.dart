import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:privastead_flutter/utilities/http_entities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'result.dart';
import 'logger.dart';

class HttpClientService {
  HttpClientService._();
  static final HttpClientService instance = HttpClientService._();

  Future<String?> _pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<Map<String, String>> _basicAuthHeaders(
    String username,
    String password, {
    bool jsonContent = false,
  }) async {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    if (jsonContent) {
      return {
        HttpHeaders.authorizationHeader: 'Basic $credentials',
        HttpHeaders.contentTypeHeader: 'application/json',
      };
    } else {
      return {HttpHeaders.authorizationHeader: 'Basic $credentials'};
    }
  }

  Future<Directory> _ensureCameraDir(String cameraName) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/camera_dir_$cameraName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _motionGroupName(String cameraName) async {
    return await getGroupName(clientTag: "motion", cameraName: cameraName);
  }

  Future<String> _livestreamGroupName(String cameraName) async {
    return await getGroupName(clientTag: "livestream", cameraName: cameraName);
  }

  /// bulk check the list of camera names against the server to check for updates
  /// returns list of corresponding cameras that have available videos for download
  Future<Result<List<String>>> bulkCheckAvailableCameras() async {
    Log.d("Entered");
    final pref = await SharedPreferences.getInstance();
    if (!pref.containsKey(PrefKeys.cameraSet)) {
      return Result.success([]);
    }

    final cameraNames = pref.getStringList(PrefKeys.cameraSet)!;
    if (cameraNames.length == 0) {
      return Result.success([]);
    }

    final serverIp = await _pref(PrefKeys.savedIp);
    final username = await _pref(PrefKeys.serverUsername);
    final password = await _pref(PrefKeys.serverPassword);

    if ([serverIp, username, password].contains(null)) {
      Log.d("Failed due to missing credentials");
      return Result.failure(Exception('Missing server credentials'));
    }

    var associatedNameToGroup = {};
    List<MotionPair> convertedCameraList = [];
    for (final cameraName in cameraNames) {
      final motionGroup = await _motionGroupName(cameraName);
      if (motionGroup == "Error!") {
        continue;
      }

      final SharedPreferencesAsync sharedPreferencesAsync =
          SharedPreferencesAsync();
      final int epoch =
          (await sharedPreferencesAsync.getInt("epoch$cameraName")) ?? 2;

      convertedCameraList.add(MotionPair(motionGroup, epoch));
      associatedNameToGroup[motionGroup] = cameraName;
    }
    Log.d("Association map: $associatedNameToGroup");

    var jsonContent = jsonEncode(MotionPairs(convertedCameraList));
    Log.d("JSON content: $jsonContent");
    final url = Uri.parse('http://$serverIp:8080/bulkCheck');
    final headers = await _basicAuthHeaders(
      username!,
      password!,
      jsonContent: true,
    );

    // Video download action
    final response = await http.post(url, headers: headers, body: jsonContent);
    final responseBody =
        response
            .body; // Format is comma separated strings representing the associated motion groups
    Log.d("Server response: $responseBody");

    final List<String> listBody = responseBody.split(",");
    final List<String> convertedToGroups = [];
    if (responseBody.isNotEmpty) {
      for (final groupName in listBody) {
        if (groupName.isNotEmpty) {
          Log.d("Iterating $groupName");
          convertedToGroups.add(associatedNameToGroup[groupName]);
        }
      }
    }
    Log.d("Response from function: $convertedToGroups");

    return Result.success(convertedToGroups);
  }

  /// saves as [fileName] then DELETEs the same URL.
  Future<Result<File>> downloadVideo({
    required String cameraName,
    required int epoch,
    required String fileName,
  }) async {
    try {
      final serverIp = await _pref(PrefKeys.savedIp);
      final username = await _pref(PrefKeys.serverUsername);
      final password = await _pref(PrefKeys.serverPassword);

      if ([serverIp, username, password].contains(null)) {
        Log.d("Failed due to missing credentials");
        return Result.failure(Exception('Missing server credentials'));
      }

      final motionGroup = await _motionGroupName(cameraName);
      Log.d("Camera Name: $cameraName, Motion Group: $motionGroup");
      final url = Uri.parse('http://$serverIp:8080/$motionGroup/$epoch');
      final headers = await _basicAuthHeaders(username!, password!);

      // Video download action
      final response = await http.get(url, headers: headers);
      if (response.statusCode != 200) {
        Log.d(
          "Failed to download file: ${response.statusCode} ${response.reasonPhrase}",
        );
        return Result.failure(
          Exception(
            'Failed to download file: ${response.statusCode} ${response.reasonPhrase}',
          ),
        );
      }

      final dir = await _ensureCameraDir(cameraName);
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      // Delete action
      final delResponse = await http.delete(url, headers: headers);
      if (delResponse.statusCode != 200) {
        Log.d(
          "Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase} ",
        );
        return Result.failure(
          Exception(
            'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
          ),
        );
      }

      Log.d("Success downloading for camera $cameraName");

      return Result.success(file);
    } catch (e) {
      Log.e('Download video error: $e');
      return Result.failure(Exception(e.toString()));
    }
  }

  /// POST /fcm_token
  Future<Result<void>> uploadFcmToken(String token) async {
    try {
      final serverIp = await _pref(PrefKeys.savedIp);
      final username = await _pref(PrefKeys.serverUsername);
      final password = await _pref(PrefKeys.serverPassword);

      Log.d("Username = $username, Pass = $password");

      if ([serverIp, username, password].contains(null)) {
        return Result.failure(Exception('Missing server credentials'));
      }

      final url = Uri.parse('http://$serverIp:8080/fcm_token');
      final headers = await _basicAuthHeaders(username!, password!);

      final response = await http.post(url, headers: headers, body: token);

      if (response.statusCode != 200) {
        return Result.failure(
          Exception(
            'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
          ),
        );
      } else {
        Log.d("Successfully sent data");
      }

      return Result.success();
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// POST /livestream/<group>
  Future<Result<void>> livestreamStart(String cameraName) async {
    try {
      final serverIp = await _pref(PrefKeys.savedIp);
      final username = await _pref(PrefKeys.serverUsername);
      final password = await _pref(PrefKeys.serverPassword);

      if ([serverIp, username, password].contains(null)) {
        return Result.failure(Exception('Missing server credentials'));
      }

      final group = await _livestreamGroupName(cameraName);
      Log.d("Group for camera: $group");
      final url = Uri.parse('http://$serverIp:8080/livestream/$group');
      final headers = await _basicAuthHeaders(username!, password!);

      final response = await http.post(url, headers: headers);
      if (response.statusCode != 200) {
        return Result.failure(
          Exception(
            'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
          ),
        );
      }

      return Result.success();
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// GET /livestream/<group>/<chunkNumber> then deletes the file
  /// using /<group>/<chunkNumber>
  Future<Result<Uint8List>> livestreamRetrieve({
    required String cameraName,
    required int chunkNumber,
  }) async {
    try {
      final serverIp = await _pref(PrefKeys.savedIp);
      final username = await _pref(PrefKeys.serverUsername);
      final password = await _pref(PrefKeys.serverPassword);

      if ([serverIp, username, password].contains(null)) {
        return Result.failure(Exception('Missing server credentials'));
      }

      final group = await _livestreamGroupName(cameraName);
      final url = Uri.parse(
        'http://$serverIp:8080/livestream/$group/$chunkNumber',
      );
      final headers = await _basicAuthHeaders(username!, password!);

      final response = await http.get(url, headers: headers);
      if (response.statusCode != 200) {
        return Result.failure(
          Exception(
            'Failed to fetch data: ${response.statusCode} ${response.reasonPhrase}',
          ),
        );
      }

      // Delete action
      final delUrl = Uri.parse('http://$serverIp:8080/$group/$chunkNumber');
      final delResponse = await http.delete(delUrl, headers: headers);
      if (delResponse.statusCode != 200) {
        Log.d(
          "Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase} ",
        );
        return Result.failure(
          Exception(
            'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
          ),
        );
      }

      return Result.success(response.bodyBytes);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }

  /// POST /livestream_end/<group>
  Future<Result<void>> livestreamEnd(String cameraName) async {
    try {
      final serverIp = await _pref(PrefKeys.savedIp);
      final username = await _pref(PrefKeys.serverUsername);
      final password = await _pref(PrefKeys.serverPassword);

      if ([serverIp, username, password].contains(null)) {
        return Result.failure(Exception('Missing server credentials'));
      }

      final group = await _livestreamGroupName(cameraName);
      Log.d("Group for camera in livestream start: $group");
      final url = Uri.parse('http://$serverIp:8080/livestream_end/$group');
      final headers = await _basicAuthHeaders(username!, password!);

      final response = await http.post(url, headers: headers);
      if (response.statusCode != 200) {
        return Result.failure(
          Exception(
            'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
          ),
        );
      }

      return Result.success();
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }
}
