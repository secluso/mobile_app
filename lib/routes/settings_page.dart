import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool isNightTheme = false;
  bool isNotificationsOn = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Load settings from shared_preferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isNightTheme = prefs.getBool('nightTheme') ?? false;
      isNotificationsOn = prefs.getBool('notifications') ?? true;
    });
  }

  // Save settings
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nightTheme', isNightTheme);
    await prefs.setBool('notifications', isNotificationsOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Colors.green[800],
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () {
            Scaffold.of(context).openDrawer();
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    title: Text("Night Theme"),
                    subtitle: Text("Enable dark mode for the app"),
                    value: isNightTheme,
                    onChanged: (value) {
                      setState(() {
                        isNightTheme = value;
                      });
                      _saveSettings();
                    },
                    secondary: Icon(Icons.dark_mode),
                  ),
                ),
                SizedBox(height: 10),
                Card(
                  child: SwitchListTile(
                    title: Text("Notifications"),
                    subtitle: Text("Receive app notifications"),
                    value: isNotificationsOn,
                    onChanged: (value) {
                      setState(() {
                        isNotificationsOn = value;
                      });
                      _saveSettings();
                    },
                    secondary: Icon(Icons.notifications_active),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
