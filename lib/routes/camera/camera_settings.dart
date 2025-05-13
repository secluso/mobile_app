import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Video Quality settings
  String selectedResolution = '1080p';
  int selectedFps = 30;

  // Mapping from resolution to available FPS options
  final Map<String, List<int>> fpsMapping = {
    '4K': [15, 30],
    '1080p': [15, 30, 60],
    '720p': [15, 30, 60],
  };

  // Notification settings
  bool notificationsEnabled = true;

  // Options: user can select "All" or choose specific events like Motion, Humans, Vehicles, or Pets.
  final List<String> notificationOptions = [
    'All',
    'Humans',
    'Vehicles',
    'Pets',
  ];
  List<String> selectedNotificationEvents = ['All'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Camera Settings"),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Video Quality Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Video Quality",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Resolution:"),
                        DropdownButton<String>(
                          value: selectedResolution,
                          onChanged: (String? newValue) {
                            setState(() {
                              selectedResolution = newValue!;
                              // Adjust FPS if current selection isn't valid for the new resolution
                              if (!fpsMapping[selectedResolution]!.contains(
                                selectedFps,
                              )) {
                                selectedFps =
                                    fpsMapping[selectedResolution]!.first;
                              }
                            });
                          },
                          items:
                              fpsMapping.keys.map((String resolution) {
                                return DropdownMenuItem<String>(
                                  value: resolution,
                                  child: Text(resolution),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Frame Rate (FPS):"),
                        DropdownButton<int>(
                          value: selectedFps,
                          onChanged: (int? newValue) {
                            setState(() {
                              selectedFps = newValue!;
                            });
                          },
                          items:
                              fpsMapping[selectedResolution]!
                                  .map(
                                    (int fps) => DropdownMenuItem<int>(
                                      value: fps,
                                      child: Text(fps.toString()),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Notification Settings Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Notification Settings",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text("Enable Notifications"),
                      value: notificationsEnabled,
                      onChanged: (bool value) {
                        setState(() {
                          notificationsEnabled = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Notify me for events:",
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children:
                          notificationOptions.map((option) {
                            final bool isSelected = selectedNotificationEvents
                                .contains(option);
                            return ChoiceChip(
                              label: Text(option),
                              selected: isSelected,
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    if (option == 'All') {
                                      selectedNotificationEvents = ['All'];
                                    } else {
                                      selectedNotificationEvents.remove('All');
                                      selectedNotificationEvents.add(option);
                                    }
                                  } else {
                                    selectedNotificationEvents.remove(option);
                                    if (selectedNotificationEvents.isEmpty) {
                                      selectedNotificationEvents = ['All'];
                                    }
                                  }
                                });
                              },
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Settings saved!"),
                    duration: Duration(seconds: 2),
                  ),
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 27, 114, 60),
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 32,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Save Settings",
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
