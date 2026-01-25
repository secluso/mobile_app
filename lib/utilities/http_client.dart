//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/epoch.dart';
import 'package:secluso_flutter/src/rust/api.dart';
import 'package:secluso_flutter/utilities/http_entities.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'result.dart';
import 'logger.dart';

// Entity used to return from download()
class DownloadResult {
  final File? file;
  final Uint8List? data;

  DownloadResult({this.file, this.data});
}

class _SilentException implements Exception {
  final String message;
  _SilentException(this.message);
  @override
  String toString() => message;
}

class FcmConfig {
  final String api_key_ios;
  final String api_key_android;
  final String app_id_ios;
  final String app_id_android;
  final String messaging_sender_id;
  final String project_id;
  final String storage_bucket;
  final String bundle_id;

  FcmConfig({
    required this.api_key_ios,
    required this.api_key_android,
    required this.app_id_ios,
    required this.app_id_android,
    required this.messaging_sender_id,
    required this.project_id,
    required this.storage_bucket,
    required this.bundle_id,
  });

  static String? _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final primary = _readString(json, key);
    if (primary != null) {
      return primary;
    }
    throw Exception('Missing $key in FCM config');
  }

  factory FcmConfig.fromJson(Map<String, dynamic> json) {
    return FcmConfig(
      api_key_ios: _requireString(json, 'api_key_ios'),
      api_key_android: _requireString(json, 'api_key_android'),
      app_id_ios: _requireString(json, 'app_id_ios'),
      app_id_android: _requireString(json, 'app_id_android'),
      messaging_sender_id: _requireString(json, 'messaging_sender_id'),
      project_id: _requireString(json, 'project_id'),
      storage_bucket: _requireString(json, 'storage_bucket'),
      bundle_id: _requireString(json, 'bundle_id'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'api_key_ios': api_key_ios,
      'api_key_android': api_key_android,
      'app_id_ios': app_id_ios,
      'app_id_android': app_id_android,
      'messaging_sender_id': messaging_sender_id,
      'project_id': project_id,
      'storage_bucket': storage_bucket,
      'bundle_id': bundle_id,
    };
  }

  static FcmConfig? fromPrefs(SharedPreferences prefs) {
    final cached = prefs.getString(PrefKeys.fcmConfigJson);
    if (cached == null || cached.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(cached);
      if (decoded is! Map<String, dynamic>) {
        Log.e("Invalid cached FCM config format");
        return null;
      }
      return FcmConfig.fromJson(decoded);
    } catch (e, st) {
      Log.e("Failed to parse cached FCM config: $e\n$st");
      return null;
    }
  }
}

class HttpClientService {
  HttpClientService._();
  static final HttpClientService instance = HttpClientService._();
  Future<void>? _versionCheckInFlight;
  bool _versionMatchConfirmed = false;
  static const Duration _groupNameInitCooldown = Duration(seconds: 30);
  static const Duration _groupNameInitTimeout = Duration(seconds: 8);
  final Map<String, DateTime> _groupNameInitLast = {};

  void resetVersionGateState() {
    _versionCheckInFlight = null;
    _versionMatchConfirmed = false;
  }

  /// bulk check the list of camera names against the server to check for updates
  /// returns list of corresponding cameras that have available videos/thumbnails for download
  /// Parameter minimumTime: The minimum amount of time the resource has been on the server to qualify for the list
  Future<Result<List<String>>> bulkCheckAvailableCameras(
    int minimumTime,
  ) => _wrap(() async {
    final pref = await SharedPreferences.getInstance();
    if (!pref.containsKey(PrefKeys.cameraSet)) {
      return [];
    }

    final cameraNames = pref.getStringList(PrefKeys.cameraSet)!;
    if (cameraNames.isEmpty) {
      return [];
    }

    final creds = await _getValidatedCredentials();

    var associatedNameToGroup = {};
    List<MotionPair> convertedCameraList = [];
    for (final cameraName in cameraNames) {
      final motionGroup = await _groupName(cameraName, Group.motion);
      if (motionGroup.startsWith("Error")) {
        continue;
      }

      final int epoch = await readEpoch(cameraName, "video");

      convertedCameraList.add(MotionPair(motionGroup, epoch));
      associatedNameToGroup[motionGroup] = cameraName;
    }
    Log.d("Association map: $associatedNameToGroup");

    var jsonContent = jsonEncode(MotionPairs(convertedCameraList));
    Log.d("JSON content: $jsonContent");
    final url = _buildUrl(creds.serverAddr, ['bulkCheck']);
    final headers = await _basicAuthHeaders(
      creds.username,
      creds.password,
      jsonContent: true,
    );

    // Bulk check fetch action
    final response = await http.post(url, headers: headers, body: jsonContent);
    await _handleServerVersionHeader(response);
    final responseBody =
        response
            .body; // Format is comma separated strings representing the associated motion groups
    Log.d("Server response: $responseBody");

    final List<dynamic> decoded = jsonDecode(responseBody);
    final List<String> convertedToGroups = [];
    final now =
        DateTime.now().millisecondsSinceEpoch ~/
        1000; // current UNIX time in seconds

    for (final item in decoded) {
      final groupName = item['group_name'] as String;
      final timestamp = item['timestamp'] as int;

      final age = now - timestamp;
      Log.d("Iterating $groupName with ts $timestamp (age=$age)");

      if (age >= minimumTime && associatedNameToGroup.containsKey(groupName)) {
        convertedToGroups.add(associatedNameToGroup[groupName]);
      }
    }
    return convertedToGroups;
  });

  Future<Result<String>> fetchServerVersion() =>
      _wrap(() async => _fetchServerVersionRaw(), bypassVersionGate: true);

  /// POST /pair — waits for camera to join pairing
  Future<Result<String>> waitForPairingStatus({
    required String pairingToken,
  }) => _wrap(() async {
    final url = _buildUrl((await _getValidatedCredentials()).serverAddr, [
      'pair',
    ]);
    final headers = await _basicAuthHeaders(
      (await _getValidatedCredentials()).username,
      (await _getValidatedCredentials()).password,
      jsonContent: true,
    );

    final request = PairingRequest(pairingToken, 'phone');
    final body = jsonEncode(request);

    Log.d("Pairing body: $body");

    final response = await http.post(url, headers: headers, body: body);
    await _handleServerVersionHeader(response);

    Log.d("Response code: ${response.statusCode}");

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to check pairing status: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(response.body);
    Log.d("Pairing response: $decoded");
    final status = decoded['status'] as String?;
    if (status == null) throw Exception('Missing status in response');

    return status;
  });

  Future<void> uploadSettings(
    String cameraName,
    ClientSettingsMessage message,
  ) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final configGroup = await _groupName(cameraName, Group.config);

    var jsonContent = jsonEncode(message);
    var encodedContent = utf8.encode(jsonContent);
    var encryptedMessage = await encryptSettingsMessage(
      cameraName: cameraName,
      data: encodedContent,
    );
    final url = _buildUrl(creds.serverAddr, [configGroup, 'app']);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.post(
      url,
      headers: headers,
      body: encryptedMessage,
    );
    await _handleServerVersionHeader(response);
    return response;
  });

  /// Downloads fcm config
  Future<Result<FcmConfig>> fetchFcmConfig() => _wrap(() async {
    Log.d("Fetching fcm config from server");

    final creds = await _getValidatedCredentials();
    final url = _buildUrl(creds.serverAddr, ['fcm_config']);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    // Fetch fcm config action
    final response = await http.get(url, headers: headers);
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw _SilentException(
          'Failed to fetch fcm config: ${response.statusCode} ${response.reasonPhrase}',
        );
      } else {
        throw Exception(
          'Failed to fetch fcm config: ${response.statusCode} ${response.reasonPhrase}',
        );
      }
    }

    print(response.body);
    Log.d("Success fetching fcm config");
    return FcmConfig.fromJson(jsonDecode(response.body));
  });

  /// Downloads file and saves as [fileName]
  Future<Result<DownloadResult>> download({
    String? destinationFile,
    required String cameraName,
    required String type, // As dictated in constants.dart
    required String serverFile, // This is epoch in motion
    Duration? timeout,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, type);
    Log.d(
      "Camera Name: $cameraName, Group Type: $type, Group: $group, Server File: $serverFile",
    );
    final url = _buildUrl(creds.serverAddr, [group, serverFile]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    // Video download action
    final responseFuture = http.get(url, headers: headers);
    final http.Response response;
    try {
      response =
          timeout == null
              ? await responseFuture
              : await responseFuture.timeout(timeout);
    } on TimeoutException {
      throw Exception(
        'Download timeout after ${timeout?.inSeconds ?? 0}s ($cameraName, $type, $serverFile)',
      );
    }
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw _SilentException(
          'Failed to download file: ${response.statusCode} ${response.reasonPhrase}',
        );
      } else {
        throw Exception(
          'Failed to download file: ${response.statusCode} ${response.reasonPhrase}',
        );
      }
    }

    File? file;
    if (destinationFile != null) {
      final dir = await _ensureCameraDir(cameraName);
      file = File('${dir.path}/$destinationFile');
      if (await file.exists()) {
        Log.d("File name $destinationFile existed already");
        await file.delete();
      }
      await file.writeAsBytes(response.bodyBytes);
    }

    Log.d("Success downloading $serverFile for camera $cameraName");
    if (destinationFile == null) {
      return DownloadResult(data: response.bodyBytes);
    } else {
      return DownloadResult(file: file);
    }
  });

  /// Deletes file at URL
  Future<Result<void>> delete({
    String? destinationFile,
    required String cameraName,
    required String type, // As dictated in constants.dart
    required String serverFile, // This is epoch in motion
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, type);
    Log.d(
      "Camera Name: $cameraName, Group Type: $type, Group: $group, Server File: $serverFile",
    );
    final url = _buildUrl(creds.serverAddr, [group, serverFile]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    // Delete action TODO: Should we retry if fail?
    final delResponse = await http.delete(url, headers: headers);
    await _handleServerVersionHeader(delResponse);
    if (delResponse.statusCode != 200) {
      if (delResponse.statusCode == 404) {
        throw _SilentException(
          'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
        );
      } else {
        throw Exception(
          'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
        );
      }
    }
    Log.d("Successfully deleted $serverFile from server");
  });

  /// POST /fcm_token
  Future<Result<void>> uploadFcmToken(String token) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final url = _buildUrl(creds.serverAddr, ['fcm_token']);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.post(url, headers: headers, body: token);
    await _handleServerVersionHeader(response);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
      );
    } else {
      Log.d("Successfully sent data");
    }
  });

  /// POST /livestream/<group>
  Future<Result<void>> livestreamStart(String cameraName) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final group = await _groupName(cameraName, Group.livestream);
    final url = _buildUrl(creds.serverAddr, ['livestream', group]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.post(url, headers: headers);
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  });

  /// GET /livestream/<group>/<chunkNumber> then deletes the file
  /// using /<group>/<chunkNumber>
  Future<Result<Uint8List>> livestreamRetrieve({
    required String cameraName,
    required int chunkNumber,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final group = await _groupName(cameraName, Group.livestream);
    final url = _buildUrl(creds.serverAddr, ['livestream', group, chunkNumber]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.get(url, headers: headers);
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch data: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    // Delete action
    final delUrl = _buildUrl(creds.serverAddr, [group, chunkNumber]);
    final delResponse = await http.delete(delUrl, headers: headers);
    await _handleServerVersionHeader(delResponse);
    if (delResponse.statusCode != 200) {
      throw Exception(
        'Failed to delete video from server: ${delResponse.statusCode} ${delResponse.reasonPhrase}',
      );
    }

    return response.bodyBytes;
  });

  /// POST /livestream_end/<group>
  Future<Result<void>> livestreamEnd(String cameraName) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, Group.livestream);
    final url = _buildUrl(creds.serverAddr, ['livestream_end', group]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.post(url, headers: headers);
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to send data: ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  });

  /// POST /config/<group>
  Future<Result<void>> configCommand({
    required String cameraName,
    required Object command,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();
    final group = await _groupName(cameraName, Group.config);
    final url = _buildUrl(creds.serverAddr, ['config', group]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.post(url, headers: headers, body: command);
    await _handleServerVersionHeader(response);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to send config command: ${response.statusCode} ${response.reasonPhrase}',
      );
    } else {
      Log.d("Successfully sent config command");
    }
  });

  /// GET /config_response/<group>
  Future<Result<Uint8List>> fetchConfigResponse({
    required String cameraName,
  }) => _wrap(() async {
    final creds = await _getValidatedCredentials();

    final group = await _groupName(cameraName, Group.config);
    final url = _buildUrl(creds.serverAddr, ['config_response', group]);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.get(url, headers: headers);
    await _handleServerVersionHeader(response);
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw _SilentException(
          'Failed to fetch config response: ${response.statusCode} ${response.reasonPhrase}',
        );
      } else {
        throw Exception(
          'Failed to fetch config response: ${response.statusCode} ${response.reasonPhrase}',
        );
      }
    } else {
      Log.d("Successfully fetched config response");
    }

    return response.bodyBytes;
  });

  /// Utility methods below

  Future<Result<T>> _wrap<T>(
    Future<T> Function() block, {
    bool bypassVersionGate = false,
  }) async {
    try {
      if (!bypassVersionGate) {
        await _ensureVersionCompatible();
      }
      return Result.success(await block());
    } catch (e, st) {
      if (e is _SilentException) {
        Log.d("HttpClientService error: $e");
      } else if (_isNetworkException(e)) {
        Log.w("HttpClientService warning: $e");
      } else {
        Log.e("HttpClientService error: $e\n$st");
      }
      return Result.failure(Exception(e.toString()));
    }
  }

  bool _isNetworkException(Object e) {
    if (e is SocketException) {
      return true;
    }
    if (e is http.ClientException && e.message.contains('SocketException')) {
      return true;
    }
    return false;
  }

  Future<void> _ensureVersionCompatible() async {
    if (VersionGate.isBlocked) {
      throw _SilentException('Version gate active');
    }
    if (_versionMatchConfirmed) {
      return;
    }
    _versionCheckInFlight ??= _checkServerVersionAndGate();
    await _versionCheckInFlight;
    _versionCheckInFlight = null;
    if (VersionGate.isBlocked) {
      throw _SilentException('Version gate active');
    }
  }

  Future<void> _handleServerVersionHeader(http.Response response) async {
    final serverVersion = response.headers['x-server-version'];
    if (serverVersion == null || serverVersion.isEmpty) {
      return;
    }

    final clientVersion = await rustLibVersion();
    if (serverVersion != clientVersion) {
      Log.i(
        'Server version ($serverVersion) differs from client version ($clientVersion)',
      );
      _versionMatchConfirmed = false;
      VersionGate.block(
        VersionGateInfo.mismatch(
          serverVersion: serverVersion,
          clientVersion: clientVersion,
        ),
      );
      throw _SilentException('Server/client version mismatch');
    }

    _versionMatchConfirmed = true;
  }

  Future<void> _checkServerVersionAndGate() async {
    try {
      final serverVersion = await _fetchServerVersionRaw();
      final clientVersion = await rustLibVersion();

      if (serverVersion != clientVersion) {
        Log.i(
          'Server version ($serverVersion) differs from client version ($clientVersion)',
        );
        _versionMatchConfirmed = false;
        VersionGate.block(
          VersionGateInfo.mismatch(
            serverVersion: serverVersion,
            clientVersion: clientVersion,
          ),
        );
        return;
      }

      _versionMatchConfirmed = true;
      VersionGate.clear();
    } catch (e) {
      Log.d('Version check failed: $e');
    }
  }

  Future<String> _fetchServerVersionRaw() async {
    final creds = await _getValidatedCredentials();

    final url = _buildUrl(creds.serverAddr, ['status']);
    final headers = await _basicAuthHeaders(creds.username, creds.password);

    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch server version: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    // Check the X-Server-Version response header.
    final serverVersion = response.headers['x-server-version'];
    if (serverVersion == null || serverVersion.isEmpty) {
      throw Exception('Missing X-Server-Version header in response');
    }

    return serverVersion;
  }

  Future<String?> _pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Uri _buildUrl(String serverAddr, List<dynamic> segments) {
    final path = segments.join('/');
    return Uri.parse('$serverAddr/$path');
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
    final dir = Directory('${base.path}/camera_dir_$cameraName/videos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<({String serverAddr, String username, String password})>
  _getValidatedCredentials() async {
    final serverAddr = await _pref(PrefKeys.serverAddr);
    final username = await _pref(PrefKeys.serverUsername);
    final password = await _pref(PrefKeys.serverPassword);

    if ([serverAddr, username, password].contains(null)) {
      throw Exception('Missing server credentials');
    }

    return (serverAddr: serverAddr!, username: username!, password: password!);
  }

  Future<String> _groupName(String cameraName, String clientTag) async {
    String groupName = await getGroupName(
      clientTag: clientTag,
      cameraName: cameraName,
    );

    if (!groupName.startsWith("Error")) {
      return groupName;
    }

    Log.w(
      "[http] getGroupName failed for $cameraName ($clientTag): $groupName",
    );

    final retryKey = "$cameraName|$clientTag";
    final now = DateTime.now();
    final lastAttempt = _groupNameInitLast[retryKey];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _groupNameInitCooldown) {
      throw _SilentException(
        'Group name unavailable for $cameraName ($clientTag)',
      );
    }

    _groupNameInitLast[retryKey] = now;
    invalidateCameraInit(cameraName);
    final initOk = await initialize(
      cameraName,
      timeout: _groupNameInitTimeout,
      force: true,
    );
    if (initOk) {
      groupName = await getGroupName(
        clientTag: clientTag,
        cameraName: cameraName,
      );
      if (!groupName.startsWith("Error")) {
        return groupName;
      }
      Log.w(
        "[http] getGroupName retry failed for $cameraName ($clientTag): $groupName",
      );
    } else {
      Log.w(
        "[http] Init failed before getGroupName retry for $cameraName ($clientTag)",
      );
    }

    throw _SilentException(
      'Group name unavailable for $cameraName ($clientTag)',
    );
  }
}
