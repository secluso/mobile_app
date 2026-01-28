//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:secluso_flutter/utilities/rust_api.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:flutter/services.dart';
import 'package:secluso_flutter/notifications/heartbeat_task.dart';
import 'package:secluso_flutter/notifications/scheduler.dart';
import 'package:secluso_flutter/src/rust/guard.dart';
import 'package:secluso_flutter/src/rust/api/logger.dart';
import 'package:secluso_flutter/utilities/rust_util.dart';
import 'package:secluso_flutter/notifications/thumbnails.dart';
import 'package:secluso_flutter/notifications/notifications.dart';
import 'routes/home_page.dart';
import "routes/theme_provider.dart";
import "package:path_provider/path_provider.dart";
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/notifications/pending_processor.dart';
import 'package:secluso_flutter/database/migration_runner.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/utilities/trace_id.dart';
import 'package:secluso_flutter/utilities/http_client.dart';
import 'package:secluso_flutter/utilities/lock.dart';
import 'package:secluso_flutter/utilities/version_gate.dart';
import 'package:secluso_flutter/utilities/ui_state.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/constants.dart';
import 'routes/server_page.dart';
import 'dart:isolate';

final ReceivePort _mainReceivePort = ReceivePort();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const queueProcessorPortName = 'queue_processor_signal_port';
const _startupPhaseCameraInit = 'camera_init';
const _startupPhasePostFirebase = 'post_firebase';
const _versionCheckRetryDelay = Duration(seconds: 30);
Timer? _versionCheckRetryTimer;
bool _versionCheckInFlight = false;

void main() {
  // Wrap main() with a zone so if something throws during init, we still attempt to close the DB.
  runZonedGuarded(
    () async {
      Log.init();
      final traceId = newTraceId('ui');
      Log.setDefaultContext(traceId);
      await Log.runWithContext(traceId, () async {
        Log.i('UI context started (id=$traceId)');
        Log.i('main() started');
        WidgetsFlutterBinding.ensureInitialized();
        UiState.markBindingReady();
        FlutterError.onError = (details) {
          Log.e('FlutterError: ${details.exceptionAsString()}');
          final stack = details.stack;
          if (stack != null) {
            Log.e(stack.toString());
          }
          if (_isAppInBackground()) {
            unawaited(
              _handleBackgroundError(
                'FlutterError: ${details.exceptionAsString()}',
              ),
            );
          }
          FlutterError.presentError(details);
        };
        ErrorWidget.builder = (details) {
          Log.e('ErrorWidget: ${details.exceptionAsString()}');
          final stack = details.stack;
          if (stack != null) {
            Log.e(stack.toString());
          }
          if (_isAppInBackground()) {
            unawaited(
              _handleBackgroundError(
                'ErrorWidget: ${details.exceptionAsString()}',
              ),
            );
          }
          return ErrorWidget(details.exception);
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          Log.e('PlatformDispatcher: $error');
          Log.e(stack.toString());
          if (_isAppInBackground()) {
            unawaited(_handleBackgroundError('PlatformDispatcher: $error'));
          }
          return true;
        };
        unawaited(Log.ensureStorageReady());
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
        runApp(const AppBootstrap());
      });
    },
    (error, stack) async {
      Log.e('Zone error: $error');
      Log.e(stack.toString());
      if (_isAppInBackground()) {
        unawaited(_handleBackgroundError('Zone error: $error'));
      }
      try {
        await AppStores.instance.close();
      } catch (_) {}
    },
  );
}

bool _isAppInBackground() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == AppLifecycleState.inactive ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}

Future<void> _handleBackgroundError(String reason) async {
  await Log.saveBackgroundSnapshot(reason: reason);
  await initLocalNotifications();
  await showSupportLogNotification();
}

Future<void> _runStartupPhase(String phase, List<String> cameraNames) async {
  if (phase == _startupPhaseCameraInit) {
    _checkServerVersion();
  }

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
    final RootIsolateToken rootToken = message['rootToken'] as RootIsolateToken;
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    DartPluginRegistrant.ensureInitialized();
    Log.init();
    final traceId = newTraceId('startup');
    Log.setDefaultContext(traceId);

    final phase = message['phase'] as String;
    final cameraNames = (message['cameraNames'] as List).cast<String>();
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

  if (kDebugMode) {
    createLogStream().listen((event) {
      var level = event.level;
      var tag = event.tag; // Represents the calling file
      final context = event.traceId ?? '';

      // For now, we filter out all Rust code that isn't from us in release mode.
      if (kReleaseMode &&
          (!tag.contains("secluso") && !tag.startsWith("src"))) {
        return;
      }

      // We filter out OpenMLS as we don't need OpenMLS logging leaking data (although this shouldn't be a risk regardless due to release only allowing info and above in logging)
      if (tag.contains("openmls")) {
        return;
      }

      Log.runWithContextSync(context, () {
        if (level == 0 || level == 1) {
          Log.d(event.msg, customLocation: event.tag);
        } else if (level == 2) {
          Log.i(event.msg, customLocation: event.tag);
        } else {
          Log.w(event.msg, customLocation: event.tag);
        }
      });
    });
  }

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

  await _runStartupPhase(_startupPhasePostFirebase, cameraNames);

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
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF8BB3EE), Color(0xFF71A0E7)],
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
                Text(
                  'Secluso',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (errorMessage == null) ...[
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white),
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

class VersionBlockScreen extends StatelessWidget {
  const VersionBlockScreen({super.key, required this.info});

  final VersionGateInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.surface, colors.surfaceVariant],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon_centered.png',
                      width: 96,
                      height: 96,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      info.title,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      info.message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: colors.surface.withOpacity(0.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colors.outline.withOpacity(0.4),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _VersionRow(
                              label: 'Server version',
                              value: info.serverVersion,
                            ),
                            const SizedBox(height: 8),
                            _VersionRow(
                              label: 'App version',
                              value: info.clientVersion,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Update or install a compatible build to continue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _handleChangeServer,
                      child: const Text('Change server'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _checkServerVersion,
                      child: const Text('Retry version check'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
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

Future<void> _handleChangeServer() async {
  final prefs = await SharedPreferences.getInstance();
  await _invalidateServerCredentials(prefs);
  HttpClientService.instance.resetVersionGateState();
  VersionGate.clear();
  _cancelVersionCheckRetry();
  final nav = navigatorKey.currentState;
  if (nav == null) {
    return;
  }
  await nav.push(
    MaterialPageRoute(
      builder: (context) => const ServerPage(showBackButton: true),
    ),
  );
}

Future<void> _checkServerVersion() async {
  if (_versionCheckInFlight) {
    return;
  }
  _versionCheckInFlight = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final hasCredentials =
        prefs.containsKey(PrefKeys.serverAddr) &&
        prefs.containsKey(PrefKeys.serverUsername) &&
        prefs.containsKey(PrefKeys.serverPassword);
    if (!hasCredentials) {
      Log.i('Skipping server version check; missing server credentials');
      _cancelVersionCheckRetry();
      return;
    }

    // Call the status endpoint and compare versions
    final serverVersionResult =
        await HttpClientService.instance.fetchServerVersion();

    if (serverVersionResult.isFailure) {
      Log.w("Failed to fetch server version: ${serverVersionResult.error}");

      // Require client to upgrade (or downgrade) their app to go further. Block screen.
      _scheduleVersionCheckRetry();
      return;
    }

    final serverVersion = serverVersionResult.value!;
    final clientVersion = await rustLibVersion();

    if (serverVersion != clientVersion) {
      Log.i(
        "Server version ($serverVersion) differs from client version ($clientVersion)",
      );
      // Require client to upgrade (or downgrade) their app to go further. Block screen.
      VersionGate.block(
        VersionGateInfo.mismatch(
          serverVersion: serverVersion,
          clientVersion: clientVersion,
        ),
      );
      _cancelVersionCheckRetry();
      return;
    }

    VersionGate.clear();
    _cancelVersionCheckRetry();
  } catch (e, st) {
    Log.e("Error checking server version: $e\n$st");
    _scheduleVersionCheckRetry();
  } finally {
    _versionCheckInFlight = false;
  }
}

void _scheduleVersionCheckRetry() {
  if (_versionCheckRetryTimer != null) {
    return;
  }
  _versionCheckRetryTimer = Timer(_versionCheckRetryDelay, () {
    _versionCheckRetryTimer = null;
    _checkServerVersion();
  });
}

void _cancelVersionCheckRetry() {
  _versionCheckRetryTimer?.cancel();
  _versionCheckRetryTimer = null;
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
  final prefs = await SharedPreferences.getInstance();
  final cameraSet = prefs.getStringList(PrefKeys.cameraSet) ?? [];
  if (cameraSet.isNotEmpty) {
    final cameraSetLookup = cameraSet.toSet();
    final filtered =
        cameraNames
            .where((cameraName) => cameraSetLookup.contains(cameraName))
            .toList();
    final dropped =
        cameraNames
            .where((cameraName) => !cameraSetLookup.contains(cameraName))
            .toList();
    if (dropped.isNotEmpty) {
      Log.w("Dropping unknown cameras from update queue: $dropped");
    }
    cameraNames = filtered;
  }
  cameraNames =
      cameraNames.where((cameraName) => cameraName.trim().isNotEmpty).toList();
  if (cameraNames.isEmpty) {
    return;
  }

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
      _checkServerVersion();
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
      builder: (context, child) {
        final base = child ?? const SizedBox.shrink();
        return ValueListenableBuilder<VersionGateInfo?>(
          valueListenable: VersionGate.notifier,
          builder: (context, gateInfo, _) {
            if (gateInfo == null) {
              return base;
            }
            return Stack(
              children: [
                base,
                Positioned.fill(child: VersionBlockScreen(info: gateInfo)),
              ],
            );
          },
        );
      },
    );
  }
}
