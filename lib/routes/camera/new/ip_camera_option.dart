import 'package:flutter/material.dart';

// TODO: Use code from Proprietary camera to finish this

class IpCameraDialog extends StatefulWidget {
  const IpCameraDialog({super.key});

  @override
  State<IpCameraDialog> createState() => _IpCameraDialogState();

  static Future<Map<String, String>?> showIpCameraPopup(
    BuildContext context,
  ) async {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false, // user must tap X or a button
      builder: (ctx) => const IpCameraDialog(),
    );
  }
}

class _IpCameraDialogState extends State<IpCameraDialog> {
  final _cameraNameController = TextEditingController();
  final _cameraIpController = TextEditingController();

  String? _qrCode;

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
    // TODO: Complete this.
    setState(() {
      _qrCode = 'DEMO-QR-5678';
    });
  }

  void _onAddCamera() {
    final cameraName = _cameraNameController.text.trim();
    final cameraIp = _cameraIpController.text.trim();

    // Return user input in a map
    Navigator.of(context).pop({
      "cameraName": cameraName,
      "cameraIp": cameraIp,
      "qrCode": _qrCode ?? 'not scanned!',
    });
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
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'QR code: ${_qrCode ?? "not scanned!"}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
