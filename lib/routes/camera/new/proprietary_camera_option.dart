import 'package:privastead_flutter/src/rust/api.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'proprietary_camera_waiting.dart';
import 'package:privastead_flutter/keys.dart';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'qr_scan.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform, Directory;
import 'package:path/path.dart' as p;

/// Popup: User connects to camera's Wi-Fi hotspot.
class ProprietaryCameraConnectDialog extends StatefulWidget {
  const ProprietaryCameraConnectDialog({super.key});

  static bool pairingCompleted = false;
  static bool pairingInProgress = false;
  static int _sessionCounter = 0;
  static int currentSessionId = 0;
  static int? boundSessionId;

  @override
  State<ProprietaryCameraConnectDialog> createState() =>
      _ProprietaryCameraConnectDialogState();

  /// Call this to start the two-step popup flow.
  /// 1) Shows ProprietaryCameraConnectDialog.
  /// 2) If user clicks "Next", replaces it with ProprietaryCameraInfoDialo].
  /// Returns a map of final camera info if completed, or null if canceled.
  static Future<Map<String, Object>?> showProprietaryCameraSetupFlow(
    BuildContext context,
  ) async {
    pairingCompleted = false;
    pairingInProgress = true;
    currentSessionId = ++_sessionCounter;

    try {
      // Show connect dialog
      final connectResult = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const ProprietaryCameraConnectDialog(),
      );

      // If user canceled or closed
      if (connectResult == null || connectResult == false) {
        return null;
      }

      // Show camera info dialog
      final infoResult = await showDialog<Map<String, Object>>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const ProprietaryCameraInfoDialog(),
      );

      ProprietaryCameraConnectDialog.pairingCompleted = true;
      ProprietaryCameraConnectDialog.boundSessionId = null;
      ProprietaryCameraConnectDialog.pairingInProgress = false;

      // Returns null if user canceled or final data if user tapped "Add Camera"
      return infoResult;
    } finally {
      // Reset regardless of outcome
      pairingInProgress = false;
    }
  }
}

class _ProprietaryCameraConnectDialogState
    extends State<ProprietaryCameraConnectDialog> {
  bool _isConnected = false;
  bool _connectivityError = false;
  bool _isConnecting = false;
  bool _exitingToNext = false;

  late final int localSessionId;

  final platform =
      Platform.isIOS
          ? MethodChannel("privastead.com/wifi")
          : MethodChannel("privastead.com/android/wifi");

  @override
  void initState() {
    super.initState();
    localSessionId = ProprietaryCameraConnectDialog.currentSessionId;
  }

  Future<void> _connectToCamera() async {
    Log.d("Entered method");
    setState(() {
      _connectivityError = false;
      _isConnecting = true;
    });
    try {
      final result = await platform.invokeMethod<String>(
        'connectToWifi',
        <String, dynamic>{'ssid': "Privastead", 'password': '12345678'},
      );
      Log.d("First result from Wifi Connect Attempt: $result");

      if (result == "connected" &&
          !ProprietaryCameraConnectDialog.pairingInProgress) {
        try {
          const platform = MethodChannel("privastead.com/android/wifi");
          await platform.invokeMethod<String>('disconnectFromWifi');
        } catch (e) {
          Log.w("WiFi disconnect failed from InfoDialog: $e");
        }

        return;
      }

      if (result == "connected") {
        if (Platform.isIOS) {
          //Connect again to ensure no awkward errors (not sure why this occurs sometimes), should be instant
          final result = await platform.invokeMethod<String>(
            'connectToWifi',
            <String, dynamic>{'ssid': "Privastead", 'password': '12345678'},
          );
          Log.d("iOS secondary result from Wifi Connect Attempt: $result");
        }

        // Do an additional ping to the camera to ensure connectivity.
        // We expect the same IP for all Raspberry Pi Cameras
        try {
          bool connected = await pingProprietaryDevice(
            cameraIp: PrefKeys.proprietaryCameraIp,
          );
          if (!mounted) return;

          if (!connected) {
            setState(() {
              _connectivityError = true;
              _isConnecting = false;
            });
          } else {
            if (localSessionId ==
                ProprietaryCameraConnectDialog.currentSessionId) {
              ProprietaryCameraConnectDialog.boundSessionId = localSessionId;
              setState(() {
                _connectivityError = false;
                _isConnected = true;
                _isConnecting = false;
              });
            }
          }
        } catch (e) {
          Log.e(e);
          if (!_isConnected) {
            setState(() {
              _connectivityError = true;
              _isConnecting = false;
            });
          }
        }
      } else {
        if (!mounted) return;
        if (!_isConnected) {
          setState(() {
            _connectivityError = true;
            _isConnecting = false;
          });
        }
      }
    } on PlatformException catch (e) {
      Log.e("Platform exception - $e");
      if (!_isConnected) {
        setState(() {
          _connectivityError = true;
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _maybeDisconnect() async {
    //TODO: Implement for iOS
    Log.d("Possibly disconnecting");

    if (_isConnected &&
        Platform.isAndroid &&
        ProprietaryCameraConnectDialog.boundSessionId == localSessionId &&
        !ProprietaryCameraConnectDialog.pairingCompleted &&
        !_exitingToNext) {
      Log.d("Disconnecting from WiFi (owned by session $localSessionId)");
      try {
        await platform.invokeMethod<String>('disconnectFromWifi');
      } catch (e) {
        Log.w("WiFi disconnect failed: $e");
      } finally {
        ProprietaryCameraConnectDialog.boundSessionId = null;
      }
    }
  }

  void _onNext() {
    _exitingToNext = true;
    // Return true to indicate we're ready to go next
    Navigator.of(context).pop(true);
  }

  void _onCancel() async {
    await _maybeDisconnect();
    ProprietaryCameraConnectDialog.pairingInProgress = false;
    // Return false or just pop with no value => indicates cancel
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final statusText =
        _isConnected
            ? 'Connected to the camera.'
            : _isConnecting
            ? 'Attempting connection...'
            : _connectivityError
            ? "Error connecting. Try again"
            : 'Not connected to the camera.';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          await _maybeDisconnect();
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _onCancel,
                    tooltip: 'Cancel',
                  ),
                ],
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Connect to Your Camera',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We need to connect to the camera. Ensure it\'s plugged in '
                'and powered on before proceeding.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Status: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          _isConnecting
                              ? Colors.orange
                              : (_isConnected ? Colors.green : Colors.red),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed:
                    _isConnected || _isConnecting
                        ? null
                        : () {
                          _connectToCamera();
                        },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Connect'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isConnected ? _onNext : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Second popup: user enters camera name, Wi-Fi details, and optional QR code.
class ProprietaryCameraInfoDialog extends StatefulWidget {
  const ProprietaryCameraInfoDialog({super.key});

  @override
  State<ProprietaryCameraInfoDialog> createState() =>
      _ProprietaryCameraInfoDialogState();
}

class _ProprietaryCameraInfoDialogState
    extends State<ProprietaryCameraInfoDialog> {
  final _cameraNameController = TextEditingController();
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();

  Uint8List? _qrCode;

  @override
  void initState() {
    super.initState();
    ProprietaryCameraConnectDialog.pairingCompleted = false;
  }

  void _onCancel() async {
    Log.d("Cancelling");
    if (!ProprietaryCameraConnectDialog.pairingCompleted &&
        ProprietaryCameraConnectDialog.pairingInProgress &&
        Platform.isAndroid) {
      try {
        const platform = MethodChannel("privastead.com/android/wifi");
        await platform.invokeMethod<String>('disconnectFromWifi');
      } catch (e) {
        Log.w("WiFi disconnect failed from InfoDialog: $e");
      }
    }
    ProprietaryCameraConnectDialog.pairingInProgress = false;
    Navigator.of(context).pop();
  }

  Future<void> _qrScan() async {
    final result = await QrScanDialog.showQrScanDialog(context);
    if (result != null) {
      setState(() {
        _qrCode = result;
      });
    } else {
      Log.d('qrScan() - User canceled scanning.');
    }
  }

  Future<void> _onAddCamera() async {
    final cameraName = _cameraNameController.text.trim();

    var sharedPreferences = await SharedPreferences.getInstance();
    var existingCameraSet =
        sharedPreferences.getStringList(PrefKeys.cameraSet) ?? [];

    // Reset these as they are no longer needed.
    if (sharedPreferences.containsKey(PrefKeys.waitingAdditionalCamera)) {
      await deregisterCamera(cameraName: cameraName);
      sharedPreferences.remove(PrefKeys.waitingAdditionalCamera);
      sharedPreferences.remove(PrefKeys.waitingAdditionalCameraTime);

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
    }

    if (existingCameraSet.contains(cameraName.toLowerCase())) {
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Please use a unique name for the camera",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }
    final wifiSsid = _wifiSsidController.text.trim();
    final wifiPassword = _wifiPasswordController.text;

    await showDialog<Map<String, Object>>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => ProprietaryCameraWaitingDialog(
            cameraName: cameraName,
            wifiSsid: wifiSsid,
            wifiPassword: wifiPassword,
            qrCode: _qrCode!,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFormComplete =
        _cameraNameController.text.trim().isNotEmpty &&
        _wifiSsidController.text.trim().isNotEmpty &&
        _qrCode != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _onCancel,
                    tooltip: 'Cancel',
                  ),
                ],
              ),
              Text(
                'Camera Information',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Make sure your smartphone is connected to the same Wi-Fi '
                'network as the camera hub.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _cameraNameController,
                decoration: const InputDecoration(
                  labelText: 'Camera Name',
                  hintText: 'e.g. Front Door',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _wifiSsidController,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi SSID',
                  hintText: 'Network Name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _wifiPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi Password',
                  hintText: '********',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'QR code: ${_qrCode != null ? "Successfully scanned" : "not scanned!"}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _qrCode == null
                      ? TextButton(
                        onPressed: _qrScan,
                        child: const Text('Scan'),
                      )
                      : const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isFormComplete ? _onAddCamera : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Add Camera'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
