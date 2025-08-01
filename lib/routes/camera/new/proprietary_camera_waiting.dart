import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/rng.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:privastead_flutter/constants.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/routes/camera/list_cameras.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:privastead_flutter/utilities/rust_util.dart';
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
    _disconnectWifiOnce();
    super.dispose();
  }

  Future<void> _disconnectWifiOnce() async {
    if (_wifiDisconnected) return;

    try {
      const platform = MethodChannel("privastead.com/wifi");
      await platform.invokeMethod<String>(
        'disconnectFromWifi',
        <String, dynamic>{'ssid': "Privastead"},
      );
      _wifiDisconnected = true;
    } catch (e) {
      Log.w("WiFi disconnect failed: $e");
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

      final success = await addCamera(
        widget.cameraName,
        Constants.proprietaryCameraIp,
        List<int>.from(widget.qrCode),
        true,
        widget.wifiSsid,
        widget.wifiPassword,
        pairingToken,
      );

      if (!success) {
        setState(
          () => _errorMessage = "Failed to send pairing data to camera.",
        );
        return;
      }

      sleep(
        const Duration(seconds: 3),
      ); // Make sure we have enough time for the other side to read before disconnecting the WiFi.

      await _disconnectWifiOnce();

      if (Platform.isIOS) {
        for (var i = 0; i < 15; i++) {
          try {
            const platform = MethodChannel("privastead.com/wifi");
            var response = await platform.invokeMethod<String>(
              'getCurrentSSID',
              <String, dynamic>{'ssid': "Privastead"},
            );

            if (response == null || response.isEmpty) {
              break;
            }
          } catch (e) {
            Log.w("WiFi fetch SSID failed: $e");
          }

          sleep(const Duration(seconds: 1));
        }
      }

      if (!mounted) return;

      sleep(
        const Duration(seconds: 3),
      ); // wait 3 seconds to let phone reconnect to wifi / disassociate from private WiFi network

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PrefKeys.lastCameraAdd, widget.cameraName);
      final status = await HttpClientService.instance.waitForPairingStatus(
        pairingToken: pairingToken,
      );

      Log.d("Returned status: $status");

      if (!mounted) return;

      if (status.isSuccess && status.value! == "paired") {
        _onPairingConfirmed();
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

  void _onPairingConfirmed() async {
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
    if (!existingSet.contains(widget.cameraName)) {
      existingSet.add(widget.cameraName);
      await prefs.setStringList(PrefKeys.cameraSet, existingSet);
      await prefs.setInt(PrefKeys.numIgnoredHeartbeatsPrefix + widget.cameraName, 0);
      await prefs.setInt(PrefKeys.cameraStatusPrefix + widget.cameraName, CameraStatus.online);
      await prefs.setInt(PrefKeys.numHeartbeatNotificationsPrefix + widget.cameraName, 0);
      await prefs.setInt(PrefKeys.lastHeartbeatTimestampPrefix + widget.cameraName, 0);
    }

    final box = AppStores.instance.cameraStore.box<Camera>();
    final camera = Camera(widget.cameraName);
    box.put(camera);

    CameraListNotifier.instance.refreshCallback?.call();

    if (!mounted) return;

    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _onRetry() async {
    var cameraName = widget.cameraName;

    // We don't know for sure if they'll try again or not.
    await _disconnectWifiOnce();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await deregisterCamera(cameraName: cameraName);
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
