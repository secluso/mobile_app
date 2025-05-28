import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/keys.dart';
import 'qr_scan.dart';
import 'package:flutter/services.dart';

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
      print('Scanned QR code: $result');
      setState(() {
        _qrCode = result;
      });
    } else {
      print('QR scan cancelled');
    }
  }

  void _onAddCamera() async {
    final cameraName = _cameraNameController.text.trim();
    final cameraIp = _cameraIpController.text.trim();

    try {
      // Optional: save to SharedPreferences or DB if needed
      final prefs = await SharedPreferences.getInstance();
      final existingCameraSet = prefs.getStringList(PrefKeys.cameraSet) ?? [];
      if (!existingCameraSet.contains(cameraName)) {
        Map<String, Object> result = new Map();
        result["type"] = "ip";
        result["cameraName"] = cameraName;

        result["qrCode"] = _qrCode ?? 'not scanned';
        result["cameraIp"] = cameraIp;
        print(result);

        Navigator.of(context).pop<Map<String, Object>>(result);
      } else {
        print("Error: Set already contains camera name.");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please use a unique name for the camera")),
        );
        return;
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to add camera: $e")));
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
