import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/routes/camera/list_cameras.dart';
import 'package:privastead_flutter/utilities/logger.dart';
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

  static _ProprietaryCameraWaitingDialogState? _currentState;

  static void completePairingForCamera(String name, DateTime timestamp) {
    Log.d("Called complete pairing for camera");
    final state = _currentState;
    if (state == null) return;
    final now = DateTime.now();
    if (state.widget.cameraName.toLowerCase() != name.toLowerCase()) return;
    if (now.difference(timestamp).inSeconds > 60) return;

    state._onPairingConfirmed();
  }

  @override
  State<ProprietaryCameraWaitingDialog> createState() =>
      _ProprietaryCameraWaitingDialogState();
}

class _ProprietaryCameraWaitingDialogState
    extends State<ProprietaryCameraWaitingDialog> {
  bool _timedOut = false;
  bool _pairingCompleted = false;

  @override
  void initState() {
    super.initState();
    ProprietaryCameraWaitingDialog._currentState = this;

    // Timer for timeout
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && !_pairingCompleted) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  void dispose() {
    ProprietaryCameraWaitingDialog._currentState = null;
    super.dispose();
  }

  void _onPairingConfirmed() async {
    if (!mounted || _pairingCompleted) return;
    Log.d("Entered method");
    _pairingCompleted = true;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool("first_time_${widget.cameraName}", true);
    prefs.remove(PrefKeys.waitingAdditionalCamera);
    prefs.remove(PrefKeys.waitingAdditionalCameraTime);

    final existingSet = prefs.getStringList(PrefKeys.cameraSet) ?? <String>[];
    if (!existingSet.contains(widget.cameraName)) {
      existingSet.add(widget.cameraName);
      await prefs.setStringList(PrefKeys.cameraSet, existingSet);
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

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await deregisterCamera(cameraName: cameraName);
    prefs.remove(PrefKeys.waitingAdditionalCamera);
    prefs.remove(PrefKeys.waitingAdditionalCameraTime);

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

  void _onContinueAnyway() {
    _onPairingConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Connecting to Camera...",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_timedOut) ...[
              SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No response from camera',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The camera didn’t confirm pairing within 30 seconds.\n\n'
                      'Please verify the Wi-Fi details below and try again.',
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
                    const SizedBox(height: 20),
                    Text(
                      'Continuing without confirmation may leave the camera in an '
                      'incomplete state. We recommend fixing the connection and retrying.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Column(
                      children: [
                        FilledButton(
                          onPressed: _onRetry,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Try Again'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () async {
                            final proceed = await showDialog<bool>(
                              context: context,
                              builder:
                                  (ctx) => AlertDialog(
                                    title: const Text(
                                      'Proceed without confirmation?',
                                    ),
                                    content: const Text(
                                      'If the camera hasn’t actually paired, it may not '
                                      'work correctly. Are you sure you want to continue?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed:
                                            () => Navigator.of(ctx).pop(true),
                                        child: const Text('Continue'),
                                      ),
                                    ],
                                  ),
                            );
                            if (proceed == true) _onContinueAnyway();
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Continue Anyway'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Please do not leave the app while pairing.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.red[300]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
