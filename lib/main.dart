//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:flutter/services.dart';
import 'package:secluso_flutter/notifications/heartbeat_task.dart';
import 'package:secluso_flutter/notifications/scheduler.dart';
import 'package:secluso_flutter/src/rust/guard.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/notifications/thumbnails.dart';
import 'routes/home_page.dart';
import "routes/theme_provider.dart";
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/notifications/pending_processor.dart';
import 'package:secluso_flutter/database/migration_runner.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/constants.dart';
import 'dart:isolate';

final ReceivePort _mainReceivePort = ReceivePort();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const queueProcessorPortName = 'queue_processor_signal_port';
const _startupPhaseCameraInit = 'camera_init';
const _startupPhasePostFirebase = 'post_firebase';

void main() {
  // Wrap main() with a zone so if something throws during init, we still attempt to close the DB.
  runZonedGuarded(
    () {
      Log.init();
      Log.i('main() started');
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const AppBootstrap());
    },
    (error, stack) async {
      try {
        await AppStores.instance.close();
      } catch (_) {}
    },
  );
}

Future<void> _runStartupPhase(String phase, List<String> cameraNames) async {
  if (phase == _startupPhaseCameraInit && cameraNames.isEmpty) {
    return;
  }

  final rootToken = RootIsolateToken.instance;
  if (rootToken == null) {
    Log.w('RootIsolateToken unavailable; running startup on main isolate');
    await _runStartupPhaseOnMain(phase, cameraNames);
    return;
  }

  final receivePort = ReceivePort();
  try {
    await Isolate.spawn(_startupPhaseEntry, {
      'sendPort': receivePort.sendPort,
      'rootToken': rootToken,
      'phase': phase,
      'cameraNames': cameraNames,
    });
  } catch (e, st) {
    Log.e('Failed to spawn startup isolate: $e\n$st');
    await _runStartupPhaseOnMain(phase, cameraNames);
    receivePort.close();
    return;
  }

  final result = await receivePort.first;
  receivePort.close();
  if (result is Map && result['error'] != null) {
    final stack = result['stack'];
    throw Exception(
      'Startup isolate failed: ${result['error']}${stack == null ? '' : '\n$stack'}',
    );
  }
}

Future<void> _runStartupPhaseOnMain(
  String phase,
  List<String> cameraNames,
) async {
  switch (phase) {
    case _startupPhaseCameraInit:
      await RustLibGuard.initOnce();
      await _initAllCameras(cameraNames: cameraNames);
      return;
    case _startupPhasePostFirebase:
      await RustLibGuard.initOnce();
      try {
        await _checkForUpdates(); // Must come before download scheduler
        await ThumbnailManager.checkThumbnailsForAll();
      } catch (e) {
        Log.d("Caught error - $e");
      }

      await DownloadScheduler.init();
      await HeartbeatScheduler.registerPeriodicTask();
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          doAllHeartbeatTasks(false);
        }),
      );
      return;
    default:
      Log.w('Unknown startup phase: $phase');
  }
}

@pragma('vm:entry-point')
void _startupPhaseEntry(Map<String, dynamic> message) async {
  final SendPort sendPort = message['sendPort'] as SendPort;
  try {
    final RootIsolateToken rootToken =
        message['rootToken'] as RootIsolateToken;
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    DartPluginRegistrant.ensureInitialized();
    Log.init();

    final phase = message['phase'] as String;
    final cameraNames =
        (message['cameraNames'] as List).cast<String>();
    await _runStartupPhaseOnMain(phase, cameraNames);
    sendPort.send({'ok': true});
  } catch (e, st) {
    Log.e('Startup isolate error: $e\n$st');
    sendPort.send({'error': e.toString(), 'stack': st.toString()});
  }
}

Future<void> _initializeApp(ThemeProvider themeProvider) async {
  Log.d("Initialization started");
  await RustLibGuard.initOnce();

  Log.d("After RustLibGuard.initOnce");

  // The native logger causes some reentrancy deadlocks.
  // Only enable if needed.
  /*
  createLogStream().listen((event) {
    var level = event.level;
    var tag = event.tag; // Represents the calling file

    // For now, we filter out all Rust code that isn't from us in release mode.
    if (kReleaseMode && (!tag.contains("secluso") && !tag.startsWith("src"))) {
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
  */

  Log.d("After createLogStream().listen()");
  await AppStores.init();
  await runMigrations(); // Must run right after App Store initialization

  final cameraNames = await _cameraNamesFromStore();
  await _runStartupPhase(
    _startupPhaseCameraInit,
    cameraNames,
  ); // Must come after App Store and Rust Lib initialization

  // We wait to initialize Firebase and the download scheduler until our cameras have been initialized
  var prefs = await SharedPreferences.getInstance();

  if (prefs.containsKey(PrefKeys.serverAddr)) {
    final fcmConfig = FcmConfig.fromPrefs(prefs);
    if (fcmConfig == null) {
      Log.e("Missing cached FCM config; clearing server credentials");
      await _invalidateServerCredentials(prefs);
    } else {
      try {
        await FirebaseInit.ensure(fcmConfig);
      } catch (e, st) {
        Log.e("Firebase init failed: $e\n$st");
      }
    }
  }

  await _runStartupPhase(
    _startupPhasePostFirebase,
    cameraNames,
  );

  QueueProcessor.instance.start();
  QueueProcessor.instance.signalNewFile();

  _mainReceivePort.listen((message) {
    if (message == 'signal_new_file') {
      QueueProcessor.instance.signalNewFile();
    }
  });

  IsolateNameServer.removePortNameMapping(queueProcessorPortName);
  IsolateNameServer.registerPortWithName(
    _mainReceivePort.sendPort,
    queueProcessorPortName,
  );

  if (FirebaseInit.isInitialized) {
    await PushNotificationService.instance.init();
  } else {
    Log.d("Skipping PushNotificationService.init; Firebase not initialized");
  }

  // Load saved dark mode state after startup work begins
  bool isDarkMode = await ThemeProvider.loadThemePreference();
  themeProvider.setTheme(isDarkMode);
  Log.d("Loaded darkTheme value: $isDarkMode");
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  final ThemeProvider _themeProvider = ThemeProvider(false);
  bool _isReady = false;
  bool _initStarted = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInitialization();
    });
  }

  Future<void> _startInitialization() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      await _initializeApp(_themeProvider);
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    } catch (e, st) {
      Log.e("Initialization failed: $e\n$st");
      if (mounted) {
        setState(() {
          _initError = "Initialization failed";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: _themeProvider)],
      child: MyApp(isReady: _isReady, initError: _initError),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceVariant,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/icon_centered.png', width: 96, height: 96),
                const SizedBox(height: 16),
                Text('Secluso', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                if (errorMessage == null) ...[
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<List<String>> _cameraNamesFromStore() async {
  final box = AppStores.instance.cameraStore.box<Camera>();
  final cameras = await box.getAllAsync();
  return cameras.map((camera) => camera.name).toList();
}

Future<void> _initAllCameras({List<String>? cameraNames}) async {
  final names = cameraNames ?? await _cameraNamesFromStore();
  for (var cameraName in names) {
    // TODO: Check if false, perhaps there's some weird error we might need to look into...
    await initialize(cameraName);
  }
}

Future<void> _invalidateServerCredentials(SharedPreferences prefs) async {
  await prefs.remove(PrefKeys.serverAddr);
  await prefs.remove(PrefKeys.serverUsername);
  await prefs.remove(PrefKeys.serverPassword);
  await prefs.remove(PrefKeys.credentialsFull);
  await prefs.remove(PrefKeys.fcmConfigJson);
}

/// Query server for cameras that have video updates and proceed to queue them for download
Future<void> _checkForUpdates() async {
  final cameraNamesResult = await HttpClientService.instance
      .bulkCheckAvailableCameras(0);

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
  const MyApp({super.key, required this.isReady, this.initError});

  final bool isReady;
  final String? initError;

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
    if (state == AppLifecycleState.resumed && widget.isReady) {
      Log.i("App Lifecycle State set to RESUMED");
      PushNotificationService.tryUploadIfNeeded(false);
      _initAllCameras(); // I'm not sure if this is necessary or not. It could be good to periodically check for initialization though.
      _checkForUpdates();
      ThumbnailManager.checkThumbnailsForAll();
      QueueProcessor.instance
          .signalNewFile(); // Try to process any new uploads now
    }

    if (state == AppLifecycleState.detached) {
      // App is about to be terminated – close the DB to release file locks.
      // No 'await' here since Flutter may be tearing down the isolate; this is best-effort.
      RustLibGuard.shutdownOnce();
      try {
        AppStores.instance.close();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    IsolateNameServer.removePortNameMapping(queueProcessorPortName);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final Widget home =
        widget.isReady
            ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                try {
                  await RustLibGuard.shutdownOnce();
                  await AppStores.instance.close();
                } catch (_) {}
                final nav = navigatorKey.currentState;
                if (nav != null && nav.canPop()) {
                  nav.pop(result);
                } else {
                  SystemNavigator.pop();
                }
              },
              child: HomePage(),
            )
            : SplashScreen(errorMessage: widget.initError);

    return MaterialApp(
      title: 'Flutter Demo',
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: themeProvider.isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: home,
    );
  }
}
