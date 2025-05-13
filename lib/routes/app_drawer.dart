import 'package:flutter/material.dart';
import 'camera/list_cameras.dart';
import 'server_page.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';

final GlobalKey<CamerasPageState> camerasPageKey =
    GlobalKey<CamerasPageState>();

class AppDrawer extends StatelessWidget {
  final Function(Widget) onNavigate;

  AppDrawer({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Drawer(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B723C), Color(0xFF137C3B)],
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
                    Icon(Icons.lock, color: Colors.white, size: 36),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privastead Camera',
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
                  () => onNavigate(CamerasPage(key: camerasPageKey)),
                ),
                _buildDrawerItem(
                  themeProvider,
                  Icons.cloud,
                  'Server',
                  () => onNavigate(ServerPage()),
                ),

                Divider(),

                SwitchListTile(
                  title: Text("Dark Mode"),
                  value: themeProvider.isDarkMode,
                  onChanged: (value) {
                    themeProvider.toggleTheme();
                  },
                  secondary: Icon(Icons.dark_mode),
                ),
              ],
            ),
          ),
        ],
      ),
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
