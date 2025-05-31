import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/notifications/firebase.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/utilities/camera_util.dart';
import 'package:privastead_flutter/utilities/logger.dart';

class ServerPage extends StatefulWidget {
  @override
  _ServerPageState createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String? serverIp;
  String? credentials;

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
      serverIp = prefs.getString(PrefKeys.savedIp);
      credentials = prefs.getString('credentials');

      hasSynced =
          serverIp != null && serverIp!.isNotEmpty && credentials != null;
      _ipController.text = serverIp ?? '';
    });
  }

  Future<void> _saveServerSettings() async {
    if (serverIp == null || serverIp!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter a valid server IP.")),
      );
      return;
    }

    Uint8List decodedCredentials = base64Decode(credentials!);
    try {
      String credentialsString = utf8.decode(decodedCredentials);

      // TODO: Check how this handles on failure... bad QR code
      if (credentialsString.length != PrefKeys.credentialsLength) {
        var len = credentialsString.length;
        Log.e(
          "Server Page Save: User credentials should be 28 characters. Current is $len",
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error processing QR code. Please try again"),
            backgroundColor: Colors.red,
          ),
        );

        credentials = null;
        return;
      }

      var serverUsername = credentialsString.substring(
        0,
        PrefKeys.usernameLength,
      );
      var serverPassword = credentialsString.substring(
        PrefKeys.usernameLength,
        PrefKeys.usernameLength + PrefKeys.passwordLength,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PrefKeys.savedIp, serverIp!);
      await prefs.setString(PrefKeys.serverUsername, serverUsername);
      await prefs.setString(PrefKeys.serverPassword, serverPassword);
      await prefs.setString('credentials', credentials!);

      Log.d("Before try upload");
      await PushNotificationService.tryUploadIfNeeded(true);
      Log.d("After try upload");

      setState(() {
        hasSynced = true;
      });

      //initialize all cameras again
      final box = AppStores.instance.cameraStore.box<Camera>();

      final allCameras = box.getAll();
      for (var camera in allCameras) {
        // TODO: Check if false, perhaps there's some weird error we might need to look into...
        await connect(camera.name);
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Server settings saved!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Potentially invalid QR code. Please try again"),
        ),
      );
      return;
    }
  }

  Future<void> _removeServerConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.savedIp);
    await prefs.remove(PrefKeys.serverUsername);
    await prefs.remove(PrefKeys.serverPassword);
    await prefs.remove('credentials');
    _isDialogOpen.value = false;
    setState(() {
      credentials = null;
      serverIp = null;
      hasSynced = false;
      _ipController.clear();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Server connection removed.")));
  }

  void _showServerIpDialog(BuildContext context, Uint8List scannedData) {
    if (_isDialogOpen.value) return;
    _isDialogOpen.value = true;

    _ipController.clear();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Enter Server IP Address"),
          content: TextField(
            controller: _ipController,
            decoration: InputDecoration(
              hintText: "Server IP",
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _isDialogOpen.value = false;
                Navigator.pop(context);
              },
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (_ipController.text.isNotEmpty) {
                  setState(() {
                    credentials = base64Encode(scannedData);
                    serverIp = _ipController.text;
                  });
                  _isDialogOpen.value = false;
                  Navigator.pop(context);
                  _saveServerSettings();
                }
              },
              child: Text("Save"),
            ),
          ],
        );
      },
    ).then((_) => _isDialogOpen.value = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    bool isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text("Server Settings", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
        leading: IconButton(
          icon: Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            Scaffold.of(context).openDrawer();
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
                            : const Color.fromARGB(255, 235, 251, 239),
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
                                  ? Colors.greenAccent
                                  : const Color.fromARGB(255, 27, 114, 60),
                        ),
                      ),
                      Divider(
                        color:
                            isDarkMode
                                ? Colors.greenAccent
                                : Colors.green.shade700,
                        thickness: 1,
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Server IP:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        serverIp ?? "",
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
                                      _showServerIpDialog(context, rawBytes);

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
