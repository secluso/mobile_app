import 'package:flutter/material.dart';
import 'package:privastead_flutter/notifications/scheduler.dart';
import 'package:privastead_flutter/src/rust/frb_generated.dart';
import 'package:privastead_flutter/src/rust/api/logger.dart';
import 'package:privastead_flutter/utilities/rust_util.dart';
import 'routes/home_page.dart';
import "routes/theme_provider.dart";
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:privastead_flutter/notifications/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/notifications/firebase.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/notifications/pending_processor.dart';
import 'package:privastead_flutter/database/migration_runner.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:privastead_flutter/utilities/lock.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/constants.dart';
import 'dart:ui';
import 'dart:isolate';

final ReceivePort _mainReceivePort = ReceivePort();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  Log.init();
  Log.i('main() started');
  WidgetsFlutterBinding.ensureInitialized();
  Log.d("After intiialize app");
  await RustLib.init();
  createLogStream().listen((event) {
    var level = event.level;
    var tag = event.tag; // Represents the calling file

    // For now, we filter out all Rust code that isn't from us in release mode.
    if (kReleaseMode &&
        (!tag.contains("privastead") && !tag.startsWith("src"))) {
      return;
    }

    // We filter out OpenMLS as we don't need OpenMLS logging leaking data (although this shouldn't be a risk regardless due to release only allowing info and above in logging)
    if (tag.contains("openmls")) {
      return;
    }

    if (level == 0 || level == 1) {
      Log.d(event.msg, customLocation: event.tag);
    } else if (level == 2) {
      Log.i(event.msg, customLocation: event.tag);
    } else {
      Log.e(event.msg, customLocation: event.tag);
    }
  });
  Log.d("After rust lib init");
  await AppStores.init();
  await runMigrations(); // Must run right after App Store initialization

  _initAllCameras(); // Must come after App Store and Rust Lib initialization

  // We wait to initialize Firebase and the download scheduler until our cameras have been initialized
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // If we face some kind of HTTP error, we don't want this to interrupt our flow
  try {
    await _checkForUpdates(); // Must come before download scheduler
  } catch (e) {
    Log.d("Caught error - $e");
  }

  await DownloadScheduler.init();
  await HeartbeatScheduler.registerAllCameraTasks();
  await HeartbeatScheduler.scheduleAllCameraOneOffTasks();

  QueueProcessor.instance.start();
  QueueProcessor.instance.signalNewFile();

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

Future<void> _initAllCameras() async {
  final box = AppStores.instance.cameraStore.box<Camera>();

  final allCameras = box.getAll();
  for (var camera in allCameras) {
    // TODO: Check if false, perhaps there's some weird error we might need to look into...
    await initialize(camera.name);
  }
}

/// Query server for cameras that have video updates and proceed to queue them for download
Future<void> _checkForUpdates() async {
  final cameraNamesResult =
      await HttpClientService.instance.bulkCheckAvailableCameras();

  if (cameraNamesResult.isFailure ||
      (cameraNamesResult.isSuccess && cameraNamesResult.value!.isEmpty)) {
    return;
  }

  var cameraNames = cameraNamesResult.value!;

  // TODO: This is essentially a clone of my previous implementation in scheduler.dart
  // Adds the camera to the waiting list if not already in there.
  if (await lock(Constants.cameraWaitingLock)) {
    try {
      Log.d("Adding to queue for $cameraNames");
      var sharedPref = SharedPreferencesAsync();
      for (final camera in cameraNames) {
        if (await sharedPref.containsKey(PrefKeys.downloadCameraQueue)) {
          var currentCameraList = await sharedPref.getStringList(
            PrefKeys.downloadCameraQueue,
          );
          if (!currentCameraList!.contains(camera)) {
            Log.d("Added to pre-existing list for $camera");
            currentCameraList.add(camera);
            await sharedPref.setStringList(
              PrefKeys.downloadCameraQueue,
              currentCameraList,
            );
          } else {
            Log.d("List already contained $camera");
          }
        } else {
          Log.d("Created new string list for $camera");
          await sharedPref.setStringList(PrefKeys.downloadCameraQueue, [
            camera,
          ]);
        }
      }
    } finally {
      // Ensure it's unlocked.
      await unlock(Constants.cameraWaitingLock);
    }
  }

  if (cameraNames.isNotEmpty) {
    DownloadScheduler.scheduleVideoDownload(""); // Empty string means all.
  }
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

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
      _initAllCameras(); // I'm not sure if this is necessary or not. It could be good to periodically check for initialization though.
      _checkForUpdates();
      QueueProcessor.instance
          .signalNewFile(); // Try to process any new uploads now
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
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: themeProvider.isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: HomePage(),
    );
  }
}
