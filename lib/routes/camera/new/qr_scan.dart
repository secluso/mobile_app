import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:privastead_flutter/keys.dart';
import 'dart:async';

/// This dialog displays the camera preview and scans for a single QR code.
/// After the first successful scan, it prompts the user for a camera name
/// and then pops the entire flow with the final data.
class QrScanDialog extends StatefulWidget {
  const QrScanDialog({super.key});

  @override
  State<QrScanDialog> createState() => _QrScanDialogState();

  static Future<Uint8List?> showQrScanDialog(BuildContext context) async {
    return showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const QrScanDialog(),
    );
  }
}

class _QrScanDialogState extends State<QrScanDialog> {
  bool _hasScannedCode = false; // ensure we only handle the first QR code
  MobileScannerController _cameraController = MobileScannerController();

  String? _errorMessage;
  Timer? _errorTimer;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _onCloseDialog() {
    // Cancel the entire QR scanning process
    Navigator.of(context).pop(null);
  }

  void _onDetectBarcode(BarcodeCapture capture) async {
    if (_hasScannedCode) return; // already handled
    final barcodes = capture.barcodes;

    for (final barcode in barcodes) {
      final rawBytes = barcode.rawBytes;
      print('Fetched raw bytes from QR code: $rawBytes');
      final rawBytesLen = rawBytes?.length;
      if (rawBytes != null && rawBytes.isNotEmpty) {
        if (rawBytesLen == PrefKeys.numCameraSecretBytes) {
          _hasScannedCode = true; // mark as handled
          // Stop the camera
          _cameraController.stop();

          Navigator.of(context).pop(rawBytes);

          // Once we return from that, break out completely
          break;
        } else {
          _showInvalidQrCode("Invalid QR code shown");
        }
      }
    }
  }

  void _showInvalidQrCode(String message) {
    if (_errorMessage != null) return; // Don't re-show until cleared

    setState(() {
      _errorMessage = message;
    });

    _errorTimer?.cancel(); // Cancel any previous timer
    _errorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: 500, // fixed height for the scanning window
        child: Column(
          children: [
            // Top bar with close (X) button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _onCloseDialog,
                  tooltip: 'Cancel',
                ),
              ],
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: MobileScanner(
                    controller: _cameraController,
                    onDetect: _onDetectBarcode,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Align the QR code inside the frame to scan.",
                style: TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
