import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'result.dart';

class HttpClientService {
  HttpClientService._();
  static final HttpClientService instance = HttpClientService._();

  Future<String?> _pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<Map<String, String>> _basicAuthHeaders(
    String username,
    String password,
  ) async {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return {HttpHeaders.authorizationHeader: 'Basic $credentials'};
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
    return await getMotionGroupName(cameraName: cameraName);
  }

  Future<String> _livestreamGroupName(String cameraName) async {
    return await getLivestreamGroupName(cameraName: cameraName);
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
        print("Failed due to missing credentials");
        return Result.failure(Exception('Missing server credentials'));
      }

      final motionGroup = await _motionGroupName(cameraName);
      print("Motion Group: $motionGroup");
      final url = Uri.parse('http://$serverIp:8080/$motionGroup/$epoch');
      final headers = await _basicAuthHeaders(username!, password!);

      // Video download action
      final response = await http.get(url, headers: headers);
      if (response.statusCode != 200) {
        print(
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
        print(
          "Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase} ",
        );
        return Result.failure(
          Exception(
            'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
          ),
        );
      }

      print("Success downloading");

      return Result.success(file);
    } catch (e) {
      print(e.toString());
      return Result.failure(Exception(e.toString()));
    }
  }

  /// POST /fcm_token
  Future<Result<void>> uploadFcmToken(String token) async {
    try {
      final serverIp = await _pref(PrefKeys.savedIp);
      final username = await _pref(PrefKeys.serverUsername);
      final password = await _pref(PrefKeys.serverPassword);

      print("Username = $username, Pass = $password");

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
        print("Successfully sent data");
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
      print("Group for camera in livestream start: $group");
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

  /// GET /livestream/<group>/<chunkNumber>
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

      return Result.success(response.bodyBytes);
    } catch (e) {
      return Result.failure(Exception(e.toString()));
    }
  }
}
