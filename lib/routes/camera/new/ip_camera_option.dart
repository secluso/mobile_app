//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/src/rust/api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/routes/camera/new/ip_camera_waiting.dart';
import 'package:secluso_flutter/keys.dart';
import 'qr_scan.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Directory;
import 'package:path/path.dart' as p;

class IpCameraDialog extends StatefulWidget {
  const IpCameraDialog({super.key});

  @override
  State<IpCameraDialog> createState() => _IpCameraDialogState();

  static Future<Map<String, Object>?> showIpCameraPopup(
    BuildContext context,
  ) async {
    return showDialog<Map<String, Object>>(
      context: context,
      barrierDismissible: false, // user must tap X or a button
      builder: (ctx) => const IpCameraDialog(),
    );
  }
}

class _IpCameraDialogState extends State<IpCameraDialog> {
  final _cameraNameController = TextEditingController();
  final _cameraIpController = TextEditingController();

  Uint8List? _qrCode;

  @override
  void dispose() {
    _cameraNameController.dispose();
    _cameraIpController.dispose();
    super.dispose();
  }

  void _onCancel() {
    Navigator.of(context).pop(null); // Return null => canceled
  }

  Future<void> _onScanQrCode() async {
    final result = await QrScanDialog.showQrScanDialog(context);
    if (result != null) {
      setState(() {
        _qrCode = result;
      });
    } else {
      Log.d('QR scan cancelled');
    }
  }

  void _onAddCamera() async {
    final cameraName = _cameraNameController.text.trim();
    final cameraIp = _cameraIpController.text.trim();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Reset these as they are no longer needed.
      if (prefs.containsKey(PrefKeys.lastCameraAdd)) {
        var lastCameraName = prefs.getString(PrefKeys.lastCameraAdd)!;
        await deregisterCamera(cameraName: lastCameraName);
        invalidateCameraInit(lastCameraName);
        prefs.remove(PrefKeys.lastCameraAdd);

        final docsDir = await getApplicationDocumentsDirectory();
        final camDir = Directory(
          p.join(docsDir.path, 'camera_dir_$lastCameraName'),
        );
        if (await camDir.exists()) {
          try {
            await camDir.delete(recursive: true);
            Log.d('Deleted camera folder: ${camDir.path}');
          } catch (e) {
            Log.e('Error deleting folder: $e');
          }
        }
      }

      final existingCameraSet = prefs.getStringList(PrefKeys.cameraSet) ?? [];
      if (!existingCameraSet.contains(cameraName)) {
        Map<String, Object> result = new Map();
        result["type"] = "ip";
        result["cameraName"] = cameraName;

        result["qrCode"] = _qrCode ?? 'not scanned';
        result["cameraIp"] = cameraIp;

        await CameraSetupStatusDialog.show(context, result);
      } else {
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
    } catch (e) {
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Failed to add camera: $e",
            style: TextStyle(color: Colors.red),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Make sure required fields are not empty
    final isFormComplete =
        _cameraNameController.text.trim().isNotEmpty &&
        _cameraIpController.text.trim().isNotEmpty;

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
                'Add IP Camera',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              Text(
                'Note: Make sure your smartphone is connected to '
                'the same Wi-Fi network as the camera hub.',
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
                  hintText: 'e.g. Backyard Camera',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cameraIpController,
                decoration: const InputDecoration(
                  labelText: 'Camera Hub IP Address',
                  hintText: '192.168.x.x',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'QR code: ${_qrCode != null ? "Successfully scanned" : "not scanned!"}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _onScanQrCode,
                    child: const Text('Scan'),
                  ),
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
