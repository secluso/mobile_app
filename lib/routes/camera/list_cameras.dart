//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';

import 'package:secluso_flutter/src/rust/api.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/notifications/firebase.dart';
import 'package:secluso_flutter/utilities/firebase_init.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:secluso_flutter/main.dart';
import 'view_camera.dart';
import 'new/show_new_camera_options.dart';
import '../../objectbox.g.dart';
import '../server_page.dart';
import '../home_page.dart';

class ThumbnailNotifier {
  ThumbnailNotifier._();
  static final ThumbnailNotifier instance = ThumbnailNotifier._();

  // emits the camera name whose thumbnail just updated
  final _controller = StreamController<String>.broadcast();
  Stream<String> get stream => _controller.stream;

  void notify(String cameraName) => _controller.add(cameraName);
}

class CameraListNotifier {
  static final CameraListNotifier instance = CameraListNotifier._();

  VoidCallback? refreshCallback;

  CameraListNotifier._();
}

class CamerasPage extends StatefulWidget {
  const CamerasPage({Key? key}) : super(key: key);

  @override
  CamerasPageState createState() => CamerasPageState();
}

class CameraCard extends StatefulWidget {
  final String cameraName;
  final IconData icon;
  final bool unreadMessages;

  const CameraCard({
    required this.cameraName,
    required this.icon,
    required this.unreadMessages,
    super.key,
  });

  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraViewPage(cameraName: widget.cameraName),
            ),
          ),
      onLongPress: () => _confirmDeleteCamera(context, widget.cameraName),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              offset: Offset(0, 4),
              blurRadius: 6,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Thumbnail + overlay logic
              Positioned.fill(child: _thumbnailWithOverlay(widget.cameraName)),

              // Name + Icon
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.cameraName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              if (widget.unreadMessages)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.notifications,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnailWithOverlay(String camName) {
    final state = context.findAncestorStateOfType<CamerasPageState>()!;
    final initial = state._thumbCache[camName];

    return FutureBuilder<Uint8List?>(
      future: state._generateThumb(camName),
      initialData: initial,
      builder: (context, snap) {
        // Prefer any bytes we have
        final bytes = snap.data ?? initial;

        final hasBytes = bytes != null;
        final image =
            hasBytes
                ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
                : const Image(
                  image: AssetImage(
                    'assets/android_thumbnail_placeholder.jpeg',
                  ),
                  fit: BoxFit.cover,
                );

        // Overlay depends on if we have a thumbnail
        final overlay = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  hasBytes
                      ? [
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.6),
                      ]
                      : [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.7),
                      ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            image,
            overlay,
            if (!hasBytes)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Text(
                    "No Image Yet",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _confirmDeleteCamera(BuildContext context, String camName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete this camera?'),
            content: const Text(
              'This will delete the camera, all its videos, and its saved folder. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
    if (confirm == true) {
      final pageState = context.findAncestorStateOfType<CamerasPageState>();
      await pageState?.deleteCamera(camName);
    }
  }
}

class CamerasPageState extends State<CamerasPage>
    with WidgetsBindingObserver, RouteAware, SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> cameras = [];
  late Future<SharedPreferences> _prefsFuture;
  late final AnimationController _controller;

  late final StreamSubscription<String> _thumbSub;

  bool _hasPlayedLockAnimation = false;

  bool _showNotificationWarning = false;

  /// cache: cam-name to thumbnail bytes (null = tried but failed)
  final Map<String, Uint8List?> _thumbCache = {};

  /// last known-good thumbnails to fall back on if a new file is corrupted
  final Map<String, Uint8List?> _thumbFallback = {};

  /// avoid running the DB query + channel call more than once at a time
  final Map<String, Future<Uint8List?>> _thumbFutures = {};

  // Poll the database every so often and update if there's currently read messages or not
  Timer? _pollingTimer;

  void invalidateThumbnail(String cameraName) {
    _thumbCache.remove(cameraName);
    _thumbFutures.remove(cameraName);
    setState(() {}); // triggers a rebuild so FutureBuilder runs again
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.0,
      upperBound: 0.85, // stop before the fade away
    );

    _thumbSub = ThumbnailNotifier.instance.stream.listen((cam) {
      // only invalidate the one that updated
      invalidateThumbnail(cam);
    });

    // Stop at the end after playing once
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.stop();
        _controller.value = 0.85;
      }
    });

    _prefsFuture = SharedPreferences.getInstance();
    _prefsFuture.then((_) => _checkNotificationStatus());

    WidgetsBinding.instance.addObserver(this);
    CameraListNotifier.instance.refreshCallback = _loadCamerasFromDatabase;
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadCamerasFromDatabase(false), // refresh from DB every 5s
    );
  }

  @override
  void didPopNext() {
    Log.d("Returned to list cameras [pop]");
    _loadCamerasFromDatabase(true); // Load this every time we enter the page.
    _checkNotificationStatus();
  }

  @override
  void didPush() {
    Log.d('Returned to list cameras [push]');
    _loadCamerasFromDatabase(true); // Load this every time we enter the page.
    _checkNotificationStatus();
  }

  @override
  void dispose() {
    _thumbSub.cancel();
    _controller.dispose();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute? route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      // regenerate on resume
      _loadCamerasFromDatabase(
        true,
      ); //this may not be up-to-date as our stream doesn't run in the background
      setState(() {});
      _checkNotificationStatus();
    }
  }

  Future<void> _checkNotificationStatus() async {
    final prefs = await _prefsFuture;
    final notificationsRequested =
        prefs.getBool(PrefKeys.notificationsEnabled) ?? true;

    if (cameras.isEmpty) {
      // We don't need to check before a camera is added.
      return;
    }

    if (!notificationsRequested) {
      setState(() => _showNotificationWarning = false);
      return;
    }

    final lastAsked = prefs.getInt(PrefKeys.lastNotificationCheck) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldown = const Duration(hours: 24).inMilliseconds;

    final status = await Permission.notification.status;

    if (status.isDenied || status.isRestricted) {
      if (now - lastAsked >= cooldown) {
        Log.d("Requesting for notifications");
        await prefs.setInt(PrefKeys.lastNotificationCheck, now);
        final result = await Permission.notification.request();

        if (mounted) {
          if (!result.isGranted) {
            setState(() => _showNotificationWarning = true);
          } else {
            setState(() => _showNotificationWarning = false);

            //TODO: This might be necessary to work on iOS. Not 100% sure.
            if (!FirebaseInit.isInitialized) {
              Log.d("Skipping FCM permission request; Firebase not initialized");
            } else {
              await FirebaseMessaging.instance.requestPermission(
                alert: true,
                badge: true,
                sound: true,
              );
            }

            // This may be the first time we have access to this after adding a camera.
            PushNotificationService.tryUploadIfNeeded(true);
          }
        }
      } else {
        setState(() => _showNotificationWarning = true);
      }
    } else if (!status.isGranted && mounted) {
      setState(() => _showNotificationWarning = true);
    } else if (status.isGranted && mounted) {
      setState(() => _showNotificationWarning = false);
    }
  }

  Future<void> deleteCamera(String cameraName) async {
    //TODO: Remove from any waiting queues. Hold a lock for this to ensure no weird errors.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.numIgnoredHeartbeatsPrefix + cameraName);
    await prefs.remove(PrefKeys.cameraStatusPrefix + cameraName);
    await prefs.remove(PrefKeys.numHeartbeatNotificationsPrefix + cameraName);
    await prefs.remove(PrefKeys.lastHeartbeatTimestampPrefix + cameraName);
    await prefs.remove(PrefKeys.firmwareVersionPrefix + cameraName);

    await deregisterCamera(cameraName: cameraName);

    final cameraBox = AppStores.instance.cameraStore.box<Camera>();
    final videoBox = AppStores.instance.videoStore.box<Video>();

    await prefs.remove("first_time_" + cameraName);

    var existingCameraSet = prefs.getStringList(PrefKeys.cameraSet) ?? [];
    existingCameraSet.remove(cameraName);
    await prefs.setStringList(PrefKeys.cameraSet, existingCameraSet);

    // Remove camera from DB
    final query = cameraBox.query(Camera_.name.equals(cameraName)).build();
    final cams = query.find();
    query.close();
    for (final cam in cams) {
      cameraBox.remove(cam.id);
    }

    // Remove videos from DB
    final videoQuery = videoBox.query(Video_.camera.equals(cameraName)).build();
    final videos = videoQuery.find();
    videoQuery.close();
    videoBox.removeMany(videos.map((v) => v.id).toList());

    // Delete camera directory
    final docsDir = await getApplicationDocumentsDirectory();
    final camDir = Directory(p.join(docsDir.path, 'camera_dir_$cameraName'));
    if (await camDir.exists()) {
      try {
        await camDir.delete(recursive: true);
        Log.d('Deleted camera folder: ${camDir.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }

    // Delete the thumbnail lock, if it exists.
    final lock = File(
      p.join(docsDir.path, 'locks', 'thumbnail$cameraName.lock'),
    );
    if (await lock.exists()) lock.delete();

    final camDirPending = Directory(
      p.join(docsDir.path, 'waiting', 'camera_$cameraName'),
    );
    if (await camDirPending.exists()) {
      try {
        await camDirPending.delete(recursive: true);
        Log.d('Deleted camera waiting folder: ${camDirPending.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }

    // Clear any thumbnail cache
    invalidateThumbnail(cameraName);

    // Reload list
    await _loadCamerasFromDatabase(false);

    // Feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted "$cameraName"',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  final _deepEq = const DeepCollectionEquality.unordered();

  Future<void> _loadCamerasFromDatabase([bool forceRun = false]) async {
    final box = AppStores.instance.cameraStore.box<Camera>();
    final all =
        (await box.getAllAsync())
            .map(
              (c) => {
                "name": c.name,
                "icon": Icons.videocam,
                "unreadMessages": c.unreadMessages,
              },
            )
            .toList();

    // Deep compare
    if (!forceRun && _deepEq.equals(all, cameras)) return;
    Log.d("Refreshing cameras from database");

    _thumbCache.clear();
    _thumbFutures.clear();
    setState(() {
      cameras
        ..clear()
        ..addAll(all);
    });
  }

  Future<String?> _latestVideoPath(String cameraName) async {
    final videoBox = AppStores.instance.videoStore.box<Video>();

    final query =
        videoBox
            .query(
              Video_.camera.equals(cameraName) & Video_.received.equals(true),
            )
            .order(Video_.id, flags: Order.descending)
            .build()
          ..limit = 1;

    final vids = query.find();
    query.close();

    if (vids.isEmpty) return null;

    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(
      docsDir.path,
      'camera_dir_$cameraName',
      'videos',
      vids.first.video,
    );
  }

  Future<Uint8List?> _generateThumb(String cameraName) {
    if (_thumbCache.containsKey(cameraName)) {
      return Future.value(_thumbCache[cameraName] ?? _thumbFallback[cameraName]);
    }
    if (_thumbFutures.containsKey(cameraName)) {
      return _thumbFutures[cameraName]!;
    }

    final future = () async {
      final fallback = _thumbFallback[cameraName];
      try {
        final bytes = await _latestThumbnailBytes(cameraName);
        if (bytes == null) {
          _thumbCache[cameraName] = fallback;
          return fallback;
        }
        _thumbCache[cameraName] = bytes;
        _thumbFallback[cameraName] = bytes;
        return bytes;
      } catch (e) {
        Log.e('Thumb load error [$cameraName]: $e');
        _thumbCache[cameraName] = fallback;
        return fallback;
      }
    }();

    _thumbFutures[cameraName] = future;
    return future;
  }

  Future<bool> _isValidImageBytes(Uint8List bytes) async {
    try {
      final image = await decodeImageFromList(bytes);
      image.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> _latestThumbnailBytes(String cameraName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docsDir.path, 'camera_dir_$cameraName', 'videos'),
    );

    if (!await dir.exists()) return null;

    final entries = await dir.list(followLinks: false).toList();
    final candidates = <MapEntry<int, File>>[];

    for (final ent in entries) {
      if (ent is! File) continue;
      if (!ent.path.toLowerCase().endsWith('.png')) continue;

      final base = p
          .basenameWithoutExtension(ent.path)
          .replaceAll("thumbnail_", "");

      final ts = int.tryParse(base);
      if (ts == null) continue;
      candidates.add(MapEntry(ts, ent));
    }

    candidates.sort((a, b) => b.key.compareTo(a.key));

    for (final candidate in candidates) {
      try {
        final bytes = await candidate.value.readAsBytes();
        if (await _isValidImageBytes(bytes)) {
          return bytes;
        }
      } catch (e) {
        Log.e("Thumbnail read error [$cameraName]: $e");
      }
    }

    return null;
  }

  // TODO: Would a database read be faster?
  Future<String?> _latestThumbnailPath(String cameraName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docsDir.path, 'camera_dir_$cameraName', 'videos'),
    );

    if (!await dir.exists()) return null;

    File? best;
    var bestTs = -1;

    // Scan all .png files, choose the largest numeric basename
    final entries = await dir.list(followLinks: false).toList();
    for (final ent in entries) {
      if (ent is! File) continue;
      if (!ent.path.toLowerCase().endsWith('.png')) continue;

      final base = p
          .basenameWithoutExtension(ent.path)
          .replaceAll("thumbnail_", "");

      final ts = int.tryParse(base);
      if (ts == null) continue;

      if (ts > bestTs) {
        bestTs = ts;
        best = ent;
      }
    }

    return best?.path;
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildHelpSheet(context),
    );
  }

  /// Builds the actual widget that appears in the bottom sheet
  Widget _buildHelpSheet(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                Icon(Icons.help_outline, size: 24),
                SizedBox(width: 8),
                Text(
                  'Need Help?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              "• Tap a camera card to see its list of videos.\n"
              "• Long press a camera card to remove it and all of its videos.\n"
              "• Use the + button to pair a new camera.",
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK, GOT IT"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: _prefsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final prefs = snapshot.data!;
        final serverHasSynced = prefs.containsKey(PrefKeys.serverUsername);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Cameras', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color.fromARGB(255, 139, 179, 238),
            leading: IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                scaffoldKey.currentState?.openDrawer();
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.white),
                tooltip: "Need Help?",
                onPressed: () => _showHelpSheet(context),
              ),
            ],
          ),
          body:
              cameras.isEmpty
                  ? Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            offset: Offset(0, 4),
                            blurRadius: 6,
                          ),
                        ],
                        gradient: const LinearGradient(
                          colors: [
                            Color.fromARGB(255, 139, 179, 238),
                            Color.fromARGB(255, 113, 160, 231),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Lottie.asset(
                                  'assets/animations/lock_animation.json',
                                  width: 180,
                                  controller: _controller,
                                  onLoaded: (composition) {
                                    _controller.duration = composition.duration;

                                    if (!_hasPlayedLockAnimation) {
                                      _controller.forward();
                                      _hasPlayedLockAnimation = true;
                                    }
                                  },
                                ),

                                const Text(
                                  'Private. Secure. Yours.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'End-to-end encrypted access. Always.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white60,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'You’re in control.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white54,
                                  ),
                                ),

                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () async {
                                    if (serverHasSynced) {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  const ShowNewCameraOptions(),
                                        ),
                                      );
                                    } else {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => ServerPage(
                                                showBackButton: true,
                                              ),
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color.fromARGB(
                                      255,
                                      139,
                                      179,
                                      238,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      !serverHasSynced
                                          ? const Text("Connect to Your Server")
                                          : const Text("Add Your First Camera"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  : Column(
                    children: [
                      if (_showNotificationWarning)
                        Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.notifications_off,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Notifications are disabled.\nPlease enable them in Settings to receive alerts.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: openAppSettings,
                                child: const Text(
                                  'Fix',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // The camera list fills the rest
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          itemCount: cameras.length,
                          itemBuilder: (context, index) {
                            final camera = cameras[index];

                            return CameraCard(
                              key: ValueKey(camera["name"]),
                              cameraName: camera["name"],
                              icon: camera["icon"],
                              unreadMessages: camera["unreadMessages"],
                            );
                          },
                        ),
                      ),
                    ],
                  ),

          // Floating Action Button for pairing a new camera via QR
          floatingActionButton:
              cameras.isNotEmpty
                  ? Padding(
                    padding: const EdgeInsets.only(right: 16.0, bottom: 16.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The text box
                        if (!serverHasSynced)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'No server connection!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        if (!serverHasSynced) const SizedBox(width: 12),

                        // The floating action button
                        FloatingActionButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => const ShowNewCameraOptions(),
                              ),
                            );
                          },
                          backgroundColor: const Color.fromARGB(
                            255,
                            139,
                            179,
                            238,
                          ),
                          tooltip: "Pair New Camera",
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                      ],
                    ),
                  )
                  : null,
        );
      },
    );
  }
}
