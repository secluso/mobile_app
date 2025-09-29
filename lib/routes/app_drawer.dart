//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'camera/list_cameras.dart';
import 'server_page.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/keys.dart';

final GlobalKey<CamerasPageState> camerasPageKey =
    GlobalKey<CamerasPageState>();

class AppDrawer extends StatefulWidget {
  final Function(Widget) onNavigate;

  AppDrawer({required this.onNavigate});

  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  late bool notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _loadNotificationPref();
  }

  void _loadNotificationPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled =
          prefs.getBool(PrefKeys.notificationsEnabled) ?? true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Drawer(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8BB3EE), Color(0xFF71A0E7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/icon_centered.png',
                      width: 48,
                      height: 48,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Secluso Camera',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              SizedBox(width: 4),
                              Text(
                                'End-to-End Encrypted',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontStyle: FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Drawer Items
          Expanded(
            child: Column(
              children: [
                _buildDrawerItem(
                  themeProvider,
                  Icons.camera_alt,
                  'Cameras',
                  () => widget.onNavigate(CamerasPage(key: camerasPageKey)),
                ),
                _buildDrawerItem(
                  themeProvider,
                  Icons.cloud,
                  'Server',
                  () => widget.onNavigate(ServerPage(showBackButton: false)),
                ),

                _buildDrawerItem(
                  themeProvider,
                  Icons.settings,
                  'Settings',
                  () => _showSettingsSheet(context, themeProvider),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet(BuildContext context, ThemeProvider themeProvider) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Settings",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  SwitchListTile(
                    title: Text("Dark Mode"),
                    value: themeProvider.isDarkMode,
                    onChanged: (_) {
                      themeProvider.toggleTheme();
                      setState(() {}); // update local switch UI
                    },
                    secondary: Icon(Icons.dark_mode),
                  ),
                  SwitchListTile(
                    title: Text("Notifications"),
                    value: notificationsEnabled,
                    onChanged: (_) async {
                      final prefs = await SharedPreferences.getInstance();
                      setState(() {
                        notificationsEnabled = !notificationsEnabled;
                        // TODO: Do we need to request notification access?
                        prefs.setBool(
                          PrefKeys.notificationsEnabled,
                          notificationsEnabled,
                        );
                      });
                    },
                    secondary: Icon(Icons.notifications),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDrawerItem(
    ThemeProvider themeProvider,
    IconData icon,
    String text,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(
        icon,
        color: themeProvider.isDarkMode ? Colors.white : Colors.black,
        size: 25,
      ),
      title: Text(text, style: TextStyle(fontSize: 18)),
      onTap: onTap,
    );
  }
}
