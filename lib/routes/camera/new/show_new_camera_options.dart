import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:privastead_flutter/routes/camera/list_cameras.dart';
import 'propietary_camera_option.dart';
import 'ip_camera_option.dart';
import 'package:privastead_flutter/utilities/camera_util.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import '../../../objectbox.g.dart';

//TODO: We need to have a check that checks if they've entered the server options, and if not, tell them to do so to avoid any weird errors
// TODO: Make the transtiion from adding a camera to be more smooth. There shouldn't be a delay between the addition -> complete setup (might confuse user)

class ShowNewCameraOptions extends StatelessWidget {
  const ShowNewCameraOptions({super.key});

  /// Navigates to the proprietary (QR) camera setup page.
  /// We return the scannedResult back to the previous page if present.
  Future<void> _navigateToProprietaryCamera(BuildContext context) async {
    print("Before show proprietary camera flow");
    final result =
        await ProprietaryCameraConnectDialog.showProprietaryCameraSetupFlow(
          context,
        );

    print("After (Proprietary camera flow)");
    if (result != null) {
      // fmt: "cameraName": cameraName, "wifiSsid": wifiSsid, "wifiPassword": wifiPassword,  "qrCode": _qrCode ?? 'not scanned',
      String cameraName = result["cameraName"]! as String;
      final res = addCamera(
        cameraName,
        PrefKeys.proprietaryCameraIp,
        List<int>.from(result["qrCode"]! as Uint8List),
        true,
        result["wifiSsid"]! as String,
        result["wifiPassword"]! as String,
      );

      res.then((t) async {
        print("Got 2 $t");

        if (t) {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setBool("first_time_" + cameraName, true);

          if (Platform.isAndroid) {
            print("Attempting to wifi disconnect");
            final platform = MethodChannel("privastead.com/android/wifi");
            final result = await platform.invokeMethod<String>(
              'disconnectFromWifi',
            );
            print("Result from disconnection: $result");
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Working on adding camera...")),
          );

          processAddCamera(cameraName);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => CamerasPage()),
          ); // Navigate back.
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

  void processAddCamera(String cameraName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool("first_time_" + cameraName, true);

    // Now we modify the list of our aggregated camera names... cameraSet
    var sharedPreferences = await SharedPreferences.getInstance();
    var existingCameraSet =
        sharedPreferences.getStringList(PrefKeys.cameraSet) ?? [];

    existingCameraSet.add(cameraName);
    await sharedPreferences.setStringList(
      PrefKeys.cameraSet,
      existingCameraSet,
    ); //Update it to include the most recent one

    // TODO: Why was the existing Android code storing a camera set when we have a database?
    final box = AppStores.instance.cameraStore.box<Camera>();

    var camera = Camera(cameraName);
    box.put(camera);

    CameraListNotifier.instance.refreshCallback?.call();
  }

  /// Navigates to IP camera setup page
  void _navigateToIPCamera(BuildContext context) async {
    print("Before show IP camera flow");
    final result = await IpCameraDialog.showIpCameraPopup(context);
    print("After (IP camera navigation start)");
    if (result != null) {
      final cameraName = result["cameraName"]! as String;
      final res = addCamera(
        cameraName,
        result["cameraIp"] as String,
        List<int>.from(result["qrCode"]! as Uint8List),
        false,
        '',
        '',
      );

      // Disconnect from WiFi if on Android

      res.then((t) async {
        print("Got 2 $t");

        if (t) {
          processAddCamera(cameraName);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add New Camera',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
        iconTheme: const IconThemeData(color: Colors.white),
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
                  Image.asset(
                    'assets/proprietary_camera_option.jpg',
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
                  Image.asset(
                    'assets/ip_camera_option.jpg',
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
