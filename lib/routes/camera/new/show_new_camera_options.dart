import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'propietary_camera_option.dart';
import 'ip_camera_option.dart';
import 'package:privastead_flutter/utilities/camera_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

//TODO: We need to have a check that checks if they've entered the server options, and if not, tell them to do so to avoid any weird errors

class ShowNewCameraOptions extends StatelessWidget {
  const ShowNewCameraOptions({super.key});

  /// Navigates to the proprietary (QR) camera setup page.
  /// We return the scannedResult back to the previous page if present.
  Future<void> _navigateToProprietaryCamera(BuildContext context) async {
    print("before");
    final result =
        await ProprietaryCameraConnectDialog.showProprietaryCameraSetupFlow(
          context,
        );

    print("After");
    if (result != null) {
      //  "cameraName": cameraName, "wifiSsid": wifiSsid, "wifiPassword": wifiPassword,  "qrCode": _qrCode ?? 'not scanned',
      print("Got $result");
      final res = addCamera(
        result["cameraName"]! as String,
        "10.42.0.1",
        List<int>.from(result["qrCode"]! as Uint8List),
        true,
        result["wifiSsid"]! as String,
        result["wifiPassword"]! as String,
      );

      res.then((t) async {
        print("Got 2 $t");

        if (t) {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setBool(
            "first_time_" + (result["cameraName"]! as String),
            true,
          );
          Navigator.pop(context, {"name": result["cameraName"]! as String});
        } else {
          // Display an error message...
          Navigator.of(context).pop(); //Empty = error...
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to add camera due to internal error"),
            ),
          );
        }
      });
      print("After");
    } else {
      debugPrint("User cancelled Proprietary camera setup");
    }
  }

  /// Navigates to your IP camera setup page
  /// TODO: This needs to be finished
  void _navigateToIPCamera(BuildContext context) async {
    final result = await IpCameraDialog.showIpCameraPopup(context);
    if (result != null) {
      // result = { "cameraName": "...", "cameraIp": "...", "qrCode": "..." }
      debugPrint('Added IP camera: $result');
    } else {
      debugPrint('User canceled IP camera setup.');
    }
    Navigator.pop(context, {"name": "My IP Camera"});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Camera'),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          // Card for proprietary camera setup
          InkWell(
            onTap: () => _navigateToProprietaryCamera(context),
            borderRadius: BorderRadius.circular(12),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.network(
                    'https://cdn-shop.adafruit.com/970x728/5025-02.jpg', // TODO: Incorporate these images into the app itself (to avoid network use)
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use Privastead\'s Official Camera',
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use our in-house camera for an easy setup and great experience.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Card for IP camera setup
          InkWell(
            onTap: () => _navigateToIPCamera(context),
            borderRadius: BorderRadius.circular(12),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.network(
                    'https://www.shutterstock.com/image-photo/surveillance-cameras-set-different-videcam-600nw-2200503529.jpg', // TODO: Incorporate these images into the app itself (to avoid network use)
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use an IP Camera',
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connect any IP-based camera by providing your camera hub\'s IP address and credentials.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
