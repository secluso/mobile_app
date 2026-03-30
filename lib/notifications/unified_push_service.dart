//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/notifications/android_push_transport.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';

const String _seclusoUnifiedPushInstance = 'secluso_android';

class UnifiedPushService {
  UnifiedPushService._();

  static final instance = UnifiedPushService._();

  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> init({bool background = false}) async {
    if (!Platform.isAndroid) {
      return;
    }
    if (_initialized) {
      return;
    }
    if (_initFuture != null) {
      return _initFuture!;
    }
    _initFuture = _doInit(background: background);
    return _initFuture!;
  }

  Future<void> _doInit({required bool background}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!background && !AndroidPushTransport.isUnifiedPrefs(prefs)) {
        return;
      }

      await UnifiedPush.initialize(
        onNewEndpoint: _onNewEndpoint,
        onRegistrationFailed: _onRegistrationFailed,
        onUnregistered: _onUnregistered,
        onMessage: _onMessage,
        onTempUnavailable: _onTempUnavailable,
      );
      _initialized = true;
    } finally {
      _initFuture = null;
    }
  }

  Future<bool> tryUseCurrentOrDefaultDistributor() async {
    await init();
    final success = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    if (success) {
      final distributor = await UnifiedPush.getDistributor();
      await _persistDistributor(distributor);
    }
    return success;
  }

  Future<List<String>> getDistributors() async {
    await init();
    return UnifiedPush.getDistributors();
  }

  Future<void> saveDistributor(String distributor) async {
    await init();
    await UnifiedPush.saveDistributor(distributor);
    await _persistDistributor(distributor);
  }

  Future<void> register() async {
    await init();
    await UnifiedPush.register(instance: _seclusoUnifiedPushInstance);
  }

  Future<bool> hasStoredEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    final endpoint =
        prefs.getString(PrefKeys.unifiedPushEndpointUrl)?.trim() ?? '';
    return endpoint.isNotEmpty;
  }

  Future<void> deactivate() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await init();
      await UnifiedPush.unregister(_seclusoUnifiedPushInstance);
    } catch (e, st) {
      Log.w('[UP] unregister failed: $e\n$st');
    }
    await _clearStoredEndpoint();
  }

  Future<void> _onNewEndpoint(PushEndpoint endpoint, String instance) async {
    if (instance != _seclusoUnifiedPushInstance) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.unifiedPushEndpointUrl, endpoint.url);
    final pubKeySet = endpoint.pubKeySet;
    if (pubKeySet != null) {
      await prefs.setString(PrefKeys.unifiedPushPubKey, pubKeySet.pubKey);
      await prefs.setString(PrefKeys.unifiedPushAuth, pubKeySet.auth);
    } else {
      await prefs.remove(PrefKeys.unifiedPushPubKey);
      await prefs.remove(PrefKeys.unifiedPushAuth);
    }
    Log.d(
      '[UP] endpoint updated '
      '(temporary=${endpoint.temporary}, hasKeys=${pubKeySet != null})',
    );

    final hasServerAddr =
        (prefs.getString(PrefKeys.serverAddr) ?? '').trim().isNotEmpty;
    if (hasServerAddr) {
      final result =
          await HttpClientService.instance.uploadNotificationTarget();
      if (result.isSuccess) {
        Log.d('[UP] notification target uploaded after endpoint update');
      } else {
        Log.w(
          '[UP] failed to upload notification target after endpoint update',
        );
      }
    }
  }

  Future<void> _onRegistrationFailed(
    FailedReason reason,
    String instance,
  ) async {
    if (instance != _seclusoUnifiedPushInstance) {
      return;
    }
    Log.w('[UP] registration failed: $reason');
  }

  Future<void> _onUnregistered(String instance) async {
    if (instance != _seclusoUnifiedPushInstance) {
      return;
    }
    Log.d('[UP] unregistered');
    await _clearStoredEndpoint();
  }

  Future<void> _onTempUnavailable(String instance) async {
    if (instance != _seclusoUnifiedPushInstance) {
      return;
    }
    Log.w('[UP] distributor temporarily unavailable');
  }

  Future<void> _onMessage(PushMessage message, String instance) async {
    if (instance != _seclusoUnifiedPushInstance) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (!message.decrypted) {
      Log.w('[UP] received encrypted message payload; skipping');
      return;
    }
    await handleEncryptedAndroidPushBytes(
      message.content,
      source: 'unifiedpush',
    );
  }

  Future<void> _persistDistributor(String? distributor) async {
    final prefs = await SharedPreferences.getInstance();
    if (distributor == null || distributor.trim().isEmpty) {
      await prefs.remove(PrefKeys.unifiedPushDistributor);
      return;
    }
    await prefs.setString(PrefKeys.unifiedPushDistributor, distributor);
  }

  Future<void> _clearStoredEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.unifiedPushEndpointUrl);
    await prefs.remove(PrefKeys.unifiedPushPubKey);
    await prefs.remove(PrefKeys.unifiedPushAuth);
  }
}
