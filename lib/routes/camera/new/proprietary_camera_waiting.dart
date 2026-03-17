//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:async';

import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/rng.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/notifications/ios_notification_relay.dart';
import 'package:secluso_flutter/routes/camera/list_cameras.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/proprietary_camera_hotspot.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/result.dart';
import 'package:secluso_flutter/notifications/notification_permissions.dart';
import 'proprietary_camera_option.dart';
import 'package:path/path.dart' as p;

class ProprietaryCameraWaitingDialog extends StatefulWidget {
  final String cameraName;
  final String wifiSsid;
  final String wifiPassword;
  final Uint8List qrCode;

  const ProprietaryCameraWaitingDialog({
    required this.cameraName,
    required this.wifiSsid,
    required this.wifiPassword,
    required this.qrCode,
    super.key,
  });

  @override
  State<ProprietaryCameraWaitingDialog> createState() =>
      _ProprietaryCameraWaitingDialogState();
}

class _ProprietaryCameraWaitingDialogState
    extends State<ProprietaryCameraWaitingDialog> {
  static const MethodChannel _wifiChannel = MethodChannel("secluso.com/wifi");
  static const String _cameraHotspotSsid = 'Secluso';
  static const Duration _cameraReadGracePeriod = Duration(seconds: 3);
  static const Duration _networkPollInterval = Duration(seconds: 1);
  static const Duration _networkReconnectTimeout = Duration(seconds: 20);
  static const Duration _pairingRetryTimeout = Duration(seconds: 20);

  bool _timedOut = false;
  bool _pairingCompleted = false;
  String? _errorMessage;
  bool _wifiDisconnected = false;

  @override
  void initState() {
    super.initState();
    _startInitialPairing();
  }

  @override
  void dispose() {
    unawaited(_disconnectWifiOnce());
    super.dispose();
  }

  Future<void> _disconnectWifiOnce() async {
    if (_wifiDisconnected) return;

    try {
      final result = await _wifiChannel.invokeMethod<String>(
        'disconnectFromWifi',
        <String, dynamic>{'ssid': _cameraHotspotSsid},
      );
      Log.d("WiFi disconnect result: ${result ?? '<null>'}");
      _wifiDisconnected = true;
    } catch (e) {
      Log.w("WiFi disconnect failed: $e");
    }
  }

  Future<String> _currentSsid() async {
    if (!Platform.isIOS) {
      return '';
    }

    try {
      final response = await _wifiChannel.invokeMethod<String>(
        'getCurrentSSID',
        <String, dynamic>{'ssid': _cameraHotspotSsid},
      );
      return response?.trim() ?? '';
    } catch (e) {
      Log.w("WiFi fetch SSID failed: $e");
      return '';
    }
  }

  Future<Uri?> _configuredServerUri() async {
    final prefs = await SharedPreferences.getInstance();
    final rawServerAddr = prefs.getString(PrefKeys.serverAddr);
    if (rawServerAddr == null || rawServerAddr.isEmpty) {
      Log.w('Server address is unavailable for reachability probe');
      return null;
    }

    try {
      return Uri.parse(rawServerAddr);
    } catch (e) {
      Log.w(
        'Invalid server address for reachability probe: $rawServerAddr ($e)',
      );
      return null;
    }
  }

  Uri _relayReachabilityUri() =>
      Uri.parse(Constants.iosNotificationRelayBaseUrl);

  String _summarizeUri(Uri uri) {
    final buffer =
        StringBuffer()
          ..write(uri.scheme)
          ..write('://')
          ..write(uri.host);
    if (uri.hasPort) {
      buffer.write(':${uri.port}');
    }
    return buffer.toString();
  }

  Future<bool> _probeTcpReachability(Uri uri) async {
    final port =
        uri.hasPort
            ? uri.port
            : (uri.scheme.toLowerCase() == 'https' ? 443 : 80);
    Socket? socket;
    try {
      socket = await Socket.connect(
        uri.host,
        port,
        timeout: const Duration(seconds: 3),
      );
      return true;
    } catch (e) {
      Log.d(
        'Reachability probe failed '
        '(target=${_summarizeUri(uri)}, error=$e)',
      );
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<({bool serverReachable, bool relayReachable})>
  _probeRequiredNetworkTargets() async {
    final serverUri = await _configuredServerUri();
    final relayUri = Platform.isIOS ? _relayReachabilityUri() : null;
    final results = await Future.wait<bool>([
      serverUri == null
          ? Future<bool>.value(false)
          : _probeTcpReachability(serverUri),
      relayUri == null
          ? Future<bool>.value(true)
          : _probeTcpReachability(relayUri),
    ]);
    return (serverReachable: results[0], relayReachable: results[1]);
  }

  bool _shouldRetryNetworkRequest(Object? error) {
    if (error == null) {
      return false;
    }

    final message = error.toString();
    return message.contains('SocketException') ||
        message.contains('Network is unreachable') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('timed out');
  }

  Future<String?> _iosRelayPairingBlocker() async {
    if (!Platform.isIOS) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final binding = loadStoredIosRelayBinding(prefs);
    if (!isStoredIosRelayBindingUsable(prefs: prefs, binding: binding)) {
      return 'iOS notification relay is not ready yet. Wait a few minutes and try pairing again.';
    }
    return null;
  }

  Future<void> _waitForPostPairConnectivity() async {
    final deadline = DateTime.now().add(_networkReconnectTimeout);
    var stablePolls = 0;

    while (DateTime.now().isBefore(deadline)) {
      final ssid = await _currentSsid();
      final probes = await _probeRequiredNetworkTargets();
      final onCameraHotspot = ssid == _cameraHotspotSsid;
      final hasReachability = probes.serverReachable && probes.relayReachable;

      if (!onCameraHotspot && hasReachability) {
        stablePolls += 1;
        if (stablePolls >= 2) {
          Log.d(
            'Network handoff completed after pairing '
            '(ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
            'serverReachable=${probes.serverReachable}, '
            'relayReachable=${probes.relayReachable})',
          );
          return;
        }
      } else {
        stablePolls = 0;
      }

      Log.d(
        'Waiting for post-pair connectivity '
        '(ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
        'onCameraHotspot=$onCameraHotspot, '
        'serverReachable=${probes.serverReachable}, '
        'relayReachable=${probes.relayReachable}, '
        'stablePolls=$stablePolls)',
      );
      await Future.delayed(_networkPollInterval);
    }

    final ssid = await _currentSsid();
    final probes = await _probeRequiredNetworkTargets();
    Log.w(
      'Timed out waiting for post-pair connectivity '
      '(ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
      'serverReachable=${probes.serverReachable}, '
      'relayReachable=${probes.relayReachable})',
    );
  }

  Future<Result<String>> _waitForPairingStatusWithRetries({
    required String pairingToken,
  }) async {
    final deadline = DateTime.now().add(_pairingRetryTimeout);
    Result<String>? lastResult;
    var attempt = 0;

    while (true) {
      attempt += 1;
      lastResult = await HttpClientService.instance.waitForPairingStatus(
        pairingToken: pairingToken,
      );
      if (lastResult.isSuccess ||
          !_shouldRetryNetworkRequest(lastResult.error) ||
          DateTime.now().isAfter(deadline)) {
        return lastResult;
      }

      final probes = await _probeRequiredNetworkTargets();
      final ssid = await _currentSsid();
      Log.w(
        'Pairing status request failed during network handoff; retrying '
        '(attempt=$attempt, '
        'ssid=${ssid.isEmpty ? '<empty>' : ssid}, '
        'serverReachable=${probes.serverReachable}, '
        'relayReachable=${probes.relayReachable}, '
        'error=${lastResult.error})',
      );
      await Future.delayed(_networkPollInterval);
    }
  }

  void _startInitialPairing() async {
    setState(() {
      _errorMessage = null;
      _timedOut = false;
      _pairingCompleted = false;
    });

    try {
      var pairingToken = Uuid().v4(config: V4Options(null, CryptoRNG()));

      final hotspotReady = await ProprietaryCameraHotspot.waitUntilReady(
        cameraIp: Constants.proprietaryCameraIp,
        timeout: const Duration(seconds: 12),
        reconnectIfNeeded: Platform.isIOS,
      );
      if (!hotspotReady) {
        if (!mounted) return;
        setState(
          () =>
              _errorMessage =
                  "Lost connection to the camera hotspot. Reconnect to the camera and try again.",
        );
        return;
      }

      final firmwareVersion = await addCamera(
        widget.cameraName,
        Constants.proprietaryCameraIp,
        List<int>.from(widget.qrCode),
        true,
        widget.wifiSsid,
        widget.wifiPassword,
        pairingToken,
      );

      if (firmwareVersion.startsWith("Error")) {
        setState(
          () => _errorMessage = "Failed to send pairing data to camera.",
        );
        return;
      }

      // Give the camera time to read the encrypted Wi-Fi payload before
      // tearing down the phone-side hotspot association.
      await Future.delayed(_cameraReadGracePeriod);

      await _disconnectWifiOnce();
      await _waitForPostPairConnectivity();

      if (!mounted) return;

      await PushNotificationService.tryUploadIfNeeded(true);
      final iosRelayBlocker = await _iosRelayPairingBlocker();
      if (iosRelayBlocker != null) {
        if (!mounted) return;
        setState(() => _errorMessage = iosRelayBlocker);
        return;
      }

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PrefKeys.lastCameraAdd, widget.cameraName);
      final status = await _waitForPairingStatusWithRetries(
        pairingToken: pairingToken,
      );

      Log.d("Returned status: $status");

      if (!mounted) return;

      if (status.isSuccess && status.value! == "paired") {
        _onPairingConfirmed(firmwareVersion);
      } else {
        setState(() => _timedOut = true);
      }

      // Backup
      Future.delayed(const Duration(seconds: 45), () {
        if (mounted && !_pairingCompleted) {
          setState(() => _timedOut = true);
        }
      });
    } catch (e) {
      setState(() => _errorMessage = "Unexpected error: $e");
    }
  }

  void _onPairingConfirmed(String firmwareVersion) async {
    if (!mounted || _pairingCompleted) return;
    // TODO: should these two lines go before the mounted check? what happens if this occurs?

    ProprietaryCameraConnectDialog.pairingCompleted =
        true; // So we don't attempt a WiFi disconnect when we pop()
    ProprietaryCameraConnectDialog.pairingInProgress = false;

    Log.d("Entered method");
    _pairingCompleted = true;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool("first_time_${widget.cameraName}", true);
    prefs.remove(PrefKeys.lastCameraAdd);

    final existingSet = prefs.getStringList(PrefKeys.cameraSet) ?? <String>[];
    final wasFirstCamera = existingSet.isEmpty;
    if (!existingSet.contains(widget.cameraName)) {
      existingSet.add(widget.cameraName);
      await prefs.setStringList(PrefKeys.cameraSet, existingSet);
      await prefs.setInt(
        PrefKeys.numIgnoredHeartbeatsPrefix + widget.cameraName,
        0,
      );
      await prefs.setInt(
        PrefKeys.cameraStatusPrefix + widget.cameraName,
        CameraStatus.online,
      );
      await prefs.setInt(
        PrefKeys.numHeartbeatNotificationsPrefix + widget.cameraName,
        0,
      );
      await prefs.setInt(
        PrefKeys.lastHeartbeatTimestampPrefix + widget.cameraName,
        0,
      );
      await prefs.setString(
        PrefKeys.firmwareVersionPrefix + widget.cameraName,
        firmwareVersion,
      );
    }

    final box = AppStores.instance.cameraStore.box<Camera>();
    final camera = Camera(widget.cameraName);
    box.put(camera);

    CameraListNotifier.instance.refreshCallback?.call();

    if (!mounted) return;

    if (wasFirstCamera) {
      await requestNotificationsAfterFirstCameraAdd();
    }

    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _onRetry() async {
    var cameraName = widget.cameraName;

    // We don't know for sure if they'll try again or not.
    await _disconnectWifiOnce();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await deregisterCamera(cameraName: cameraName);
    invalidateCameraInit(cameraName);
    HttpClientService.instance.clearGroupNameCache(cameraName);
    prefs.remove(PrefKeys.lastCameraAdd);

    final docsDir = await getApplicationDocumentsDirectory();
    final camDir = Directory(p.join(docsDir.path, 'camera_dir_$cameraName'));
    if (await camDir.exists()) {
      try {
        await camDir.delete(recursive: true);
        Log.d('Deleted camera folder: ${camDir.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }

    if (!mounted) return;
    int count = 0;
    Navigator.popUntil(context, (route) {
      count++;
      return count == 3;
    });
  }

  Widget _buildWaitingView() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Text(
        "Waiting for camera to confirm pairing...",
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Text(
        "Please do not leave the app.",
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
      ),
    ],
  );

  Widget _buildTimeoutView() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'No response from camera',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        'The camera didn’t confirm pairing within 30 seconds. Please verify the Wi-Fi details below and try again.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SSID:  ${widget.wifiSsid}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'PW:     ${widget.wifiPassword}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Continuing without confirmation may leave the camera in an incomplete state.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _onRetry,
              child: const Text("Try Again"),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildSuccessView() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 60),
      const SizedBox(height: 20),
      Text(
        'Camera successfully paired!',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _buildErrorView() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
      const SizedBox(height: 16),
      Text(
        _errorMessage ?? 'An unknown error occurred.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: () => _onRetry(), child: const Text("Back")),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child:
                    _errorMessage != null
                        ? _buildErrorView()
                        : _pairingCompleted
                        ? _buildSuccessView()
                        : _timedOut
                        ? _buildTimeoutView()
                        : _buildWaitingView(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
