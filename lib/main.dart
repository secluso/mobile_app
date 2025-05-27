import 'package:flutter/material.dart';
import 'package:privastead_flutter/notifications/scheduler.dart';
import 'package:privastead_flutter/src/rust/frb_generated.dart';
import 'package:privastead_flutter/src/rust/api/logger.dart';
import 'package:privastead_flutter/utilities/camera_util.dart';
import 'routes/home_page.dart';
import "routes/theme_provider.dart";
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'notifications/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications/firebase.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/database/entities.dart';

void main() async {
  print("Start");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("After intiialize app");
  await RustLib.init();
  print("After rust lib init");
  await AppStores.init();
  await DownloadScheduler.init();

  createLogStream().listen((event) {
    print(
      '[${event.level}] ${event.tag}: ${event.msg} (rust_time=${event.timeMillis})',
    );
  });

  await PushNotificationService.instance.init();

  // Load saved dark mode state before starting the app
  bool isDarkMode = await ThemeProvider.loadThemePreference();
  print("Loaded darkTheme value: $isDarkMode");

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(isDarkMode),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPrefs();
    _initAllCameras();
  }

  Future<void> _initPrefs() async {
    print("Initializing prefs");
    prefs = await SharedPreferences.getInstance();
    PushNotificationService.tryUploadIfNeeded(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("Resuming work");
      PushNotificationService.tryUploadIfNeeded(false);
      _initAllCameras();
    }
  }

  Future<void> _initAllCameras() async {
    final box = AppStores.instance.cameraStore.box<Camera>();

    final allCameras = box.getAll();
    for (var camera in allCameras) {
      // TODO: Check if false, perhaps there's some weird error we might need to look into...
      await connect(camera.name);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Flutter Demo',
      theme: themeProvider.isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: HomePage(),
    );
  }
}
