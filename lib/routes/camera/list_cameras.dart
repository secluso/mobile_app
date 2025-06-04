import 'package:flutter/material.dart';
import 'package:privastead_flutter/src/rust/api.dart';
import 'view_camera.dart';
import 'new/show_new_camera_options.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/main.dart';
import '../../objectbox.g.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';

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

class _CameraCardState extends State<CameraCard> {
  bool hasImage = false;

  @override
  Widget build(BuildContext context) {
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
              // Thumbnail
              Positioned.fill(
                child:
                    Platform.isIOS
                        ? _cameraThumbnailPlaceholder(widget.cameraName)
                        : const Image(
                          image: AssetImage(
                            'assets/android_thumbnail_placeholder.jpeg',
                          ),
                          fit: BoxFit.cover,
                        ),
              ),

              // Overlay depending on image presence
              if (!hasImage && Platform.isIOS) ...[
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.7),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
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
              ] else ...[
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.6),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],

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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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

  Widget _cameraThumbnailPlaceholder(String camName) {
    return FutureBuilder<Uint8List?>(
      future: context
          .findAncestorStateOfType<CamerasPageState>()!
          ._generateThumb(camName),
      builder: (context, snap) {
        final data = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (data != null && !hasImage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => hasImage = true);
          });
        }

        return SizedBox.expand(
          child:
              data != null
                  ? Image.memory(data, fit: BoxFit.cover)
                  : Container(color: Colors.black),
        );
      },
    );
  }
}

class CamerasPageState extends State<CamerasPage>
    with WidgetsBindingObserver, RouteAware {
  final List<Map<String, dynamic>> cameras = [];
  final _ch = MethodChannel('privastead.com/thumbnail');

  /// cache: cam-name to thumbnail bytes (null = tried but failed)
  final Map<String, Uint8List?> _thumbCache = {};

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
    WidgetsBinding.instance.addObserver(this);
    CameraListNotifier.instance.refreshCallback = _loadCamerasFromDatabase;

    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadCamerasFromDatabase(), // refresh from DB every 5s
    );
  }

  @override
  void didPopNext() {
    Log.d("Returned to list cameras [pop]");
    _loadCamerasFromDatabase(); // Load this every time we enter the page.
  }

  @override
  void didPush() {
    Log.d('Returned to list cameras [push]');
    _loadCamerasFromDatabase(); // Load this every time we enter the page.
  }

  @override
  void dispose() {
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
      _thumbCache.clear();
      _thumbFutures.clear();
      setState(() {});
    }
  }

  Future<void> deleteCamera(String cameraName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await deregisterCamera(cameraName: cameraName);

    final cameraBox = AppStores.instance.cameraStore.box<Camera>();
    final videoBox = AppStores.instance.videoStore.box<Video>();

    await prefs.remove("first_time_" + cameraName);

    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.remove("epoch" + cameraName);

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
    await _loadCamerasFromDatabase();

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

  Future<void> _loadCamerasFromDatabase() async {
    final box = AppStores.instance.cameraStore.box<Camera>();
    final allCameras = box.getAll();

    setState(() {
      cameras.clear();
      cameras.addAll(
        allCameras.map(
          (cam) => {
            "name": cam.name,
            "icon": Icons.videocam,
            "unreadMessages": cam.unreadMessages,
          },
        ),
      );
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
    return p.join(docsDir.path, 'camera_dir_$cameraName', vids.first.video);
  }

  Future<Uint8List?> _generateThumb(String cameraName) {
    // already cached?
    if (_thumbCache.containsKey(cameraName)) {
      return Future.value(_thumbCache[cameraName]);
    }
    // already running?
    if (_thumbFutures.containsKey(cameraName)) {
      return _thumbFutures[cameraName]!;
    }

    final future = () async {
      final path = await _latestVideoPath(cameraName);
      if (path == null) return null; // no videos yet

      try {
        final bytes = await _ch
            .invokeMethod<Uint8List>('generateThumbnail', {
              'path': path,
              'fullSize': true,
            })
            .timeout(const Duration(seconds: 3));
        _thumbCache[cameraName] = bytes; // save even null
        return bytes;
      } on Exception catch (e) {
        Log.e('Error - $cameraName: $e');
        _thumbCache[cameraName] = null;
        return null;
      }
    }();

    _thumbFutures[cameraName] = future;
    return future;
  }

  Widget cameraThumbnailPlaceholder(
    String camName,
    void Function(bool hasThumb) setHasThumb,
  ) {
    return FutureBuilder<Uint8List?>(
      future: _generateThumb(camName),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 80,
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final data = snap.data;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setHasThumb(data != null); // send result to caller
        });
        return SizedBox.expand(
          child:
              data != null
                  ? Image.memory(data, fit: BoxFit.cover)
                  : Container(color: Colors.black),
        );
      },
    );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cameras', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            Scaffold.of(context).openDrawer();
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
                        Color.fromARGB(255, 27, 114, 60),
                        Color.fromARGB(255, 54, 178, 98),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.security, color: Colors.white, size: 60),
                      const SizedBox(height: 16),
                      const Text(
                        'Hey! Welcome to Privastead',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '"A camera you can trust"\nEnd-to-end encrypted.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          // Same action as the FAB to add a new camera
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => const ShowNewCameraOptions(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color.fromARGB(
                            255,
                            27,
                            114,
                            60,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("Add Your First Camera"),
                      ),
                    ],
                  ),
                ),
              )
              : Column(
                children: [
                  // The camera list fills the rest
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      itemCount: cameras.length,
                      itemBuilder: (context, index) {
                        final camera = cameras[index];

                        return CameraCard(
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Same action as the FAB to add a new camera
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ShowNewCameraOptions(),
            ),
          );
        },
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
        tooltip: "Pair New Camera",
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
