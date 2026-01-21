//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'home_page.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:secluso_flutter/utilities/http_client.dart';

class ServerPage extends StatefulWidget {
  final bool showBackButton;

  const ServerPage({super.key, required this.showBackButton});

  @override
  _ServerPageState createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String? serverAddr;

  final TextEditingController _ipController = TextEditingController();
  bool hasSynced = false;
  ValueNotifier<bool> _isDialogOpen = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _loadServerSettings();
  }

  Future<void> _loadServerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      serverAddr = prefs.getString(PrefKeys.serverAddr);
      final credentialsFull = prefs.getString(PrefKeys.credentialsFull);

      hasSynced =
          serverAddr != null &&
          serverAddr!.isNotEmpty &&
          credentialsFull != null;
      _ipController.text = serverAddr ?? '';
    });
  }

  Future<void> _saveServerSettings(Uint8List credentialsFull) async {
    try {
      String credentialsFullString = utf8.decode(credentialsFull);

      // TODO: Check how this handles on failure... bad QR code
      if (credentialsFullString.length <=
          (Constants.usernameLength + Constants.passwordLength)) {
        var len = credentialsFull.length;
        Log.e(
          "Server Page Save: User credentials should be more than 28 characters. Current is $len",
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error processing QR code. Please try again"),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      var serverUsername = credentialsFullString.substring(
        0,
        Constants.usernameLength,
      );
      var serverPassword = credentialsFullString.substring(
        Constants.usernameLength,
        Constants.usernameLength + Constants.passwordLength,
      );

      final newServerAddr = credentialsFullString.substring(
        Constants.usernameLength + Constants.passwordLength,
        credentialsFullString.length,
      );

      //TODO: check to make sure serverIp is a valid IP address.

      final prefs = await SharedPreferences.getInstance();
      final prevServerAddr = prefs.getString(PrefKeys.serverAddr);
      final prevUsername = prefs.getString(PrefKeys.serverUsername);
      final prevPassword = prefs.getString(PrefKeys.serverPassword);
      final prevCredentialsFull = prefs.getString(PrefKeys.credentialsFull);
      final prevHasSynced =
          prevServerAddr != null &&
          prevServerAddr.isNotEmpty &&
          prevCredentialsFull != null;

      await prefs.setString(PrefKeys.serverAddr, newServerAddr);
      await prefs.setString(PrefKeys.serverUsername, serverUsername);
      await prefs.setString(PrefKeys.serverPassword, serverPassword);
      HttpClientService.instance.resetVersionGateState();

      final fetched = await HttpClientService.instance.fetchFcmConfig();
      if (fetched.isFailure || fetched.value == null) {
        if (prevServerAddr == null) {
          await prefs.remove(PrefKeys.serverAddr);
        } else {
          await prefs.setString(PrefKeys.serverAddr, prevServerAddr);
        }
        if (prevUsername == null) {
          await prefs.remove(PrefKeys.serverUsername);
        } else {
          await prefs.setString(PrefKeys.serverUsername, prevUsername);
        }
        if (prevPassword == null) {
          await prefs.remove(PrefKeys.serverPassword);
        } else {
          await prefs.setString(PrefKeys.serverPassword, prevPassword);
        }
        if (prevCredentialsFull == null) {
          await prefs.remove(PrefKeys.credentialsFull);
        } else {
          await prefs.setString(PrefKeys.credentialsFull, prevCredentialsFull);
        }
        HttpClientService.instance.resetVersionGateState();

        setState(() {
          serverAddr = prevServerAddr;
          hasSynced = prevHasSynced;
          _ipController.text = prevServerAddr ?? '';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              "Failed to fetch FCM config. Server settings not saved.",
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
        return;
      }

      await prefs.setString(
        PrefKeys.fcmConfigJson,
        jsonEncode(fetched.value!.toJson()),
      );
      await prefs.setString(PrefKeys.credentialsFull, credentialsFullString);

      setState(() {
        serverAddr = newServerAddr;
        hasSynced = true;
      });

      //initialize all cameras again
      final box = AppStores.instance.cameraStore.box<Camera>();

      final allCameras = await box.getAllAsync();
      for (var camera in allCameras) {
        // TODO: Check if false, perhaps there's some weird error we might need to look into...
        await initialize(camera.name);
      }

      bool firebaseReady = false;
      try {
        await FirebaseInit.ensure(fetched.value!);
        firebaseReady = true;
      } catch (e, st) {
        Log.e("Firebase init failed: $e\n$st");
      }

      if (firebaseReady) {
        await PushNotificationService.instance.init();
        Log.d("Before try upload");
        await PushNotificationService.tryUploadIfNeeded(true);
        Log.d("After try upload");
      } else {
        Log.d("Skipping push setup; Firebase not initialized");
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Server settings saved!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Potentially invalid QR code. Please try again",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }
  }

  Future<void> _removeServerConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.serverAddr);
    await prefs.remove(PrefKeys.serverUsername);
    await prefs.remove(PrefKeys.serverPassword);
    await prefs.remove(PrefKeys.credentialsFull);
    await prefs.remove(PrefKeys.fcmConfigJson);
    HttpClientService.instance.resetVersionGateState();
    _isDialogOpen.value = false;
    setState(() {
      serverAddr = null;
      hasSynced = false;
      _ipController.clear();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Server connection removed.")));
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    bool isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text("Server Settings", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 139, 179, 238),
        leading:
            widget.showBackButton
                ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
                : Builder(
                  builder: (context) {
                    return IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () {
                        scaffoldKey.currentState?.openDrawer();
                      },
                    );
                  },
                ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            hasSynced
                ? Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color:
                        isDarkMode
                            ? Colors.grey[900]
                            : const Color.fromARGB(255, 203, 216, 236),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: isDarkMode ? Colors.black87 : Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Connected to Server",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              isDarkMode
                                  ? Color.fromARGB(255, 139, 179, 238)
                                  : const Color.fromARGB(255, 139, 179, 238),
                        ),
                      ),
                      Divider(
                        color:
                            isDarkMode
                                ? Color.fromARGB(255, 139, 179, 238)
                                : Color.fromARGB(255, 139, 179, 238),
                        thickness: 1,
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Server Address:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        serverAddr ?? "",
                        style: TextStyle(
                          fontSize: 16,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _removeServerConnection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: Text(
                          "Remove Connection",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                : Text(
                  "Scan the server credentials using the QR code scanner.",
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
            SizedBox(height: 20),

            if (!hasSynced) ...[
              Text(
                "Scan Server Credentials",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              SizedBox(height: 10),
              ValueListenableBuilder<bool>(
                valueListenable: _isDialogOpen,
                builder: (context, isDialogOpen, child) {
                  return Container(
                    width: double.infinity,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDarkMode ? Colors.white54 : Colors.grey,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        isDialogOpen
                            ? Container(
                              color: isDarkMode ? Colors.black54 : Colors.black,
                            ) // Darker contrast for visibility
                            : MobileScanner(
                              onDetect: (BarcodeCapture capture) {
                                final List<Barcode> barcodes = capture.barcodes;
                                if (barcodes.isNotEmpty) {
                                  for (final barcode in barcodes) {
                                    final rawBytes = barcode.rawBytes;
                                    Log.d(
                                      'Fetched raw bytes from QR code: $rawBytes',
                                    );
                                    if (rawBytes != null &&
                                        rawBytes.isNotEmpty) {
                                      _saveServerSettings(rawBytes);

                                      // Once we return from that, break out completely
                                      break;
                                    }
                                  }
                                }
                              },
                            ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
