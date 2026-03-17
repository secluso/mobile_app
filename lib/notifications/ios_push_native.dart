//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../keys.dart';
import '../utilities/logger.dart';

typedef IosPushPayloadHandler =
    Future<void> Function(Map<String, dynamic> payload, String source);
typedef IosPushTokenHandler = Future<void> Function(String token);

class AppAttestAttestation {
  final String keyId;
  final String attestationObject;

  const AppAttestAttestation({
    required this.keyId,
    required this.attestationObject,
  });
}

class AppAttestAssertion {
  final String keyId;
  final String assertion;
  final String clientDataJson;

  const AppAttestAssertion({
    required this.keyId,
    required this.assertion,
    required this.clientDataJson,
  });
}

class IosPushNativeBridge {
  IosPushNativeBridge._();

  static const MethodChannel _channel = MethodChannel(
    'secluso.com/ios_push_relay',
  );

  static bool _initialized = false;
  static IosPushPayloadHandler? _payloadHandler;
  static IosPushTokenHandler? _tokenHandler;

  static Future<void> init({
    required IosPushPayloadHandler onPayload,
    IosPushTokenHandler? onToken,
  }) async {
    _payloadHandler = onPayload;
    _tokenHandler = onToken;
    if (_initialized) {
      Log.d('iOS push native bridge already initialized');
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    Log.d('Initialized iOS push native bridge');
  }

  static Future<void> registerForRemoteNotifications() async {
    Log.d('Requesting iOS remote notification registration');
    await _channel.invokeMethod<void>('registerForRemoteNotifications');
  }

  static Future<String?> getApnsToken() async {
    return _channel.invokeMethod<String>('getApnsToken');
  }

  static Future<List<Map<String, dynamic>>> drainPendingPushPayloads() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>(
          'drainPendingPushPayloads',
        ) ??
        const <dynamic>[];
    final payloads = raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (payloads.isNotEmpty) {
      Log.d('Drained pending iOS push payloads (count=${payloads.length})');
    }
    return payloads;
  }

  static Future<String> ensureAppAttestKey() async {
    Log.d('Ensuring iOS App Attest key');
    final keyId = await _channel.invokeMethod<String>('ensureAppAttestKey');
    if (keyId == null || keyId.isEmpty) {
      throw Exception('App Attest key identifier is missing');
    }
    Log.d('Resolved iOS App Attest key (key=${_summarizeOpaque(keyId)})');
    return keyId;
  }

  static Future<String> rotateAppAttestKey() async {
    Log.d('Rotating iOS App Attest key');
    final keyId = await _channel.invokeMethod<String>('rotateAppAttestKey');
    if (keyId == null || keyId.isEmpty) {
      throw Exception('Rotated App Attest key identifier is missing');
    }
    Log.d('Rotated iOS App Attest key (key=${_summarizeOpaque(keyId)})');
    return keyId;
  }

  static Future<AppAttestAttestation> attestKey(String challenge) async {
    Log.d(
      'Requesting iOS App Attest attestation '
      '(challenge=${_summarizeOpaque(challenge)})',
    );
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'attestKey',
      {'challenge': challenge},
    );
    if (raw == null) {
      throw Exception('App Attest attestation response is missing');
    }
    final data = Map<String, dynamic>.from(raw);
    final response = AppAttestAttestation(
      keyId: (data['keyId'] ?? '').toString(),
      attestationObject: (data['attestationObject'] ?? '').toString(),
    );
    Log.d(
      'Received iOS App Attest attestation '
      '(key=${_summarizeOpaque(response.keyId)}, '
      'attestationObjectLen=${response.attestationObject.length})',
    );
    return response;
  }

  static Future<AppAttestAssertion> generateAssertion(String challenge) async {
    Log.d(
      'Requesting iOS App Attest assertion '
      '(challenge=${_summarizeOpaque(challenge)})',
    );
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'generateAssertion',
      {'challenge': challenge},
    );
    if (raw == null) {
      throw Exception('App Attest assertion response is missing');
    }
    final data = Map<String, dynamic>.from(raw);
    final response = AppAttestAssertion(
      keyId: (data['keyId'] ?? '').toString(),
      assertion: (data['assertion'] ?? '').toString(),
      clientDataJson: (data['clientDataJson'] ?? '').toString(),
    );
    Log.d(
      'Received iOS App Attest assertion '
      '(key=${_summarizeOpaque(response.keyId)}, '
      'assertionLen=${response.assertion.length}, '
      'clientDataJsonLen=${response.clientDataJson.length})',
    );
    return response;
  }

  static Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'pushPayload':
        final payload = _coercePayload(call.arguments);
        Log.d(
          'Received native iOS push payload '
          '(hasPayload=${payload != null}, keys=${payload?.keys.join(",") ?? "none"})',
        );
        if (payload != null && _payloadHandler != null) {
          await _payloadHandler!(payload, 'ios-apns-live');
        }
        return;
      case 'apnsTokenUpdated':
        final token = (call.arguments ?? '').toString();
        if (token.isEmpty) {
          Log.w('Received empty APNs token update from native bridge');
          return;
        }
        Log.d(
          'Received APNs token update from native bridge '
          '(token=${_summarizeOpaque(token)})',
        );
        final prefs = await SharedPreferences.getInstance();
        final previousToken = prefs.getString(PrefKeys.iosApnsToken) ?? '';
        await prefs.setString(PrefKeys.iosApnsToken, token);
        if (previousToken != token) {
          await prefs.setBool(PrefKeys.needUpdateIosRelayBinding, true);
        } else {
          Log.d('Ignoring unchanged APNs token update for relay binding state');
        }
        if (_tokenHandler != null) {
          await _tokenHandler!(token);
        }
        return;
      default:
        Log.w('Unhandled iOS push native call: ${call.method}');
    }
  }

  static Map<String, dynamic>? _coercePayload(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  static String _summarizeOpaque(String? value) {
    if (value == null) {
      return 'null';
    }
    if (value.isEmpty) {
      return 'empty';
    }
    if (value.length <= 12) {
      return '$value(len=${value.length})';
    }
    final prefix = value.substring(0, 6);
    final suffix = value.substring(value.length - 4);
    return '$prefix...$suffix(len=${value.length})';
  }
}
