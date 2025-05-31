import 'package:flutter/material.dart';
import 'package:privastead_flutter/notifications/scheduler.dart';
import 'package:privastead_flutter/src/rust/frb_generated.dart';
import 'package:privastead_flutter/src/rust/api/logger.dart';
import 'package:privastead_flutter/utilities/camera_util.dart';
import 'routes/home_page.dart';
import "routes/theme_provider.dart";
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:privastead_flutter/notifications/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/notifications/firebase.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/notifications/pending_processor.dart';
import 'package:privastead_flutter/database/migration_runner.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'dart:ui';
import 'dart:isolate';

final ReceivePort _mainReceivePort = ReceivePort();

void main() async {
  Log.init();
  Log.i('main() started');
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Log.d("After intiialize app");
  await RustLib.init();
  Log.d("After rust lib init");
  await AppStores.init();
  await runMigrations();
  await DownloadScheduler.init();

  QueueProcessor.instance.start();
  QueueProcessor.instance.signalNewFile();

  createLogStream().listen((event) {
    Log.d(
      'Rust Log: [${event.level}] ${event.tag}: ${event.msg} (rust_time=${event.timeMillis})',
    );
  });

  _mainReceivePort.listen((message) {
    if (message == 'signal_new_file') {
      QueueProcessor.instance.signalNewFile();
    }
  });

  IsolateNameServer.registerPortWithName(
    _mainReceivePort.sendPort,
    'queue_processor_signal_port',
  );

  await PushNotificationService.instance.init();

  // Load saved dark mode state before starting the app
  bool isDarkMode = await ThemeProvider.loadThemePreference();
  Log.d("Loaded darkTheme value: $isDarkMode");

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(isDarkMode)),
      ],
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
    Log.d("Initializing prefs");
    prefs = await SharedPreferences.getInstance();
    PushNotificationService.tryUploadIfNeeded(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Log.i("App Lifecycle State set to RESUMED");
      PushNotificationService.tryUploadIfNeeded(false);
      _initAllCameras();
      QueueProcessor.instance
          .signalNewFile(); // Try to process any new uploads now
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
