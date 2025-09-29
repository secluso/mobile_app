//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'ip_camera_option.dart';
import 'proprietary_camera_option.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:flutter/services.dart';

//TODO: We need to have a check that checks if they've entered the server options, and if not, tell them to do so to avoid any weird errors

class ShowNewCameraOptions extends StatelessWidget {
  const ShowNewCameraOptions({super.key});

  /// Navigates to the proprietary (QR) camera setup page.
  Future<void> _navigateToProprietaryCamera(BuildContext context) async {
    PushNotificationService.tryUploadIfNeeded(true); //force
    await ProprietaryCameraConnectDialog.showProprietaryCameraSetupFlow(
      context,
    );
  }

  /// Navigates to IP camera setup page
  void _navigateToIPCamera(BuildContext context) async {
    Log.d("Before show IP camera flow");
    PushNotificationService.tryUploadIfNeeded(true); //force
    await IpCameraDialog.showIpCameraPopup(context);
    Log.d("After (IP camera navigation start)");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add New Camera',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 139, 179, 238),
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
                          'Use Secluso\'s Official Camera',
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
