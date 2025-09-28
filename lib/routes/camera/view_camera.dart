import 'package:flutter/material.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:objectbox/objectbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme_provider.dart';
import 'view_video.dart';
import 'view_livestream.dart';
import 'camera_settings.dart';
import '../../objectbox.g.dart';
import 'package:secluso_flutter/database/entities.dart';
import 'package:path_provider/path_provider.dart';
import 'package:secluso_flutter/database/app_stores.dart';
import 'package:secluso_flutter/utilities/logger.dart';
import 'package:secluso_flutter/main.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

_CameraViewPageState? globalCameraViewPageState;

class CameraViewPage extends StatefulWidget {
  final String cameraName;
  const CameraViewPage({super.key, required this.cameraName});

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

String repackageVideoTitle(String videoFileName) {
  if (videoFileName.startsWith("video_") && videoFileName.endsWith(".mp4")) {
    var timeOf = int.parse(
      videoFileName.replaceAll("video_", "").replaceAll(".mp4", ""),
    );
    final date =
        DateTime.fromMillisecondsSinceEpoch(
          timeOf * 1000,
          isUtc: true,
        ).toLocal();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  return videoFileName;
}

class _CameraViewPageState extends State<CameraViewPage> with RouteAware {
  late Box<Video> _videoBox;
  final List<Video> _videos = [];
  final Map<String, Uint8List?> _videoThumbCache = {};
  final Map<String, Future<Uint8List?>> _videoThumbFutures = {};

  late Box<Detection> _detectionBox;
  final Map<int, Set<String>> _detCache = {};

  static const int _pageSize = 20;
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = false;

  final ScrollController _scrollController = ScrollController();
  final ConfettiController _confetti = ConfettiController(
    duration: const Duration(seconds: 2),
  );

  /// We store an unreadMessages flag instead of iterating through all videos to be more efficient
  Future<void> _markCameraRead() async {
    final cameraBox = AppStores.instance.cameraStore.box<Camera>();
    final cameraQuery =
        cameraBox.query(Camera_.name.equals(widget.cameraName)).build();

    final foundCamera = cameraQuery.findFirst();
    cameraQuery.close();

    if (foundCamera != null && foundCamera.unreadMessages) {
      foundCamera.unreadMessages = false;
      // Save the updated row; wrap in a transaction for safety.
      cameraBox.put(foundCamera);
    }
  }

  @override
  void initState() {
    super.initState();
    globalCameraViewPageState = this;
    _scrollController.addListener(_maybeLoadNextPage);
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
  void didPopNext() {
    Log.d("Returned to view camera [pop]");
    _markCameraRead(); // Load this every time we enter the page.
    _initDbAndFirstPage();
  }

  @override
  void didPush() {
    Log.d('Returned to view camera [push]');
    _markCameraRead(); // Load this every time we enter the page.
    _initDbAndFirstPage();
  }

  Future<void> _prefetchDetectionsFor(List<Video> vids) async {
    for (final v in vids) {
      final vidPath = v.video;

      // Build the cache (types that actually match this video's file path)
      final matchingTypes = <String>{};

      final q =
          _detectionBox.query(Detection_.videoFile.equals(vidPath)).build();

      final detsForVid = q.find();
      q.close();

      for (final d in detsForVid) {
        if (d.type.isNotEmpty) matchingTypes.add(d.type.toLowerCase());
      }
      _detCache[v.id] = matchingTypes;
    }
  }

  Future<void> _initDbAndFirstPage() async {
    _videoBox = AppStores.instance.videoStore.box<Video>();
    _detectionBox = AppStores.instance.detectionStore.box<Detection>();
    await _loadNextPage(); // first 20

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final cameraName = widget.cameraName;
    var cameraStatus =
        prefs.getInt(PrefKeys.cameraStatusPrefix + cameraName) ??
        CameraStatus.online;
    Log.d("Viewing camera: camera status = $cameraStatus");

    if (cameraStatus == CameraStatus.offline ||
        cameraStatus == CameraStatus.corrupted ||
        cameraStatus == CameraStatus.possiblyCorrupted) {
      late final String msg;

      if (cameraStatus == CameraStatus.offline) {
        msg = "Camera ($cameraName) seems to be offline.";
      } else if (cameraStatus == CameraStatus.corrupted) {
        msg = "Camera ($cameraName) is corrupted. Pair again.";
      } else {
        //possiblyCorrupted
        msg = "Camera ($cameraName) is likely corrupted. Pair again.";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _confetti.dispose();
    _scrollController.dispose();
    globalCameraViewPageState = null;

    super.dispose();
  }

  Future<void> reloadVideos() async {
    final query =
        _videoBox
            .query(Video_.camera.equals(widget.cameraName))
            .order(Video_.id, flags: Order.descending)
            .build()
          ..limit = _pageSize;

    final newVideos = query.find();
    query.close();

    await _prefetchDetectionsFor(newVideos);

    setState(() {
      _videos.clear();
      _videos.addAll(newVideos);
      _hasMore = newVideos.length == _pageSize;
    });
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);

    final query =
        _videoBox
            .query(Video_.camera.equals(widget.cameraName))
            .order(Video_.id, flags: Order.descending)
            .build()
          ..limit = _pageSize
          ..offset = _offset;

    final List<Video> batch = query.find();
    query.close();

    await _prefetchDetectionsFor(batch);

    setState(() {
      _videos.addAll(batch);
      _offset += batch.length;
      _hasMore = batch.length == _pageSize;
      _isLoading = false;
    });
  }

  void _maybeLoadNextPage() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoading) {
      _loadNextPage();
    }
  }

  // Useful for debugging
  /*
  Future<void> _printAllFiles(String cameraName) async {
    Log.d("_printAllFiles called for $cameraName");
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'camera_dir_$cameraName'));

    if (!await dir.exists()) return;

    Log.d("printing all files in the camera directory");
    final entries = await dir.list(followLinks: false).toList();
    for (final ent in entries) {
      Log.d("_printAllFiles: $cameraName: ${ent.path}");
    }

    final videosDir = Directory(p.join(dir.path, 'videos'));

    if (!await videosDir.exists()) return;

    Log.d("printing all files in the camera's video directory");
    final ventries = await videosDir.list(followLinks: false).toList();
    for (final ent in ventries) {
      Log.d("_printAllFiles: $cameraName: ${ent.path}");
    }
  }
  */

  void _deleteAllVideos() async {
    HapticFeedback.heavyImpact();
    _confetti.play();

    final dir = await getApplicationDocumentsDirectory();
    final videoDir = Directory(
      '${dir.path}/camera_dir_${widget.cameraName}/videos',
    );

    // Delete the videos directory
    if (await videoDir.exists()) {
      try {
        await videoDir.delete(recursive: true);
        Log.d('Deleted camera folder: ${videoDir.path}');
      } catch (e) {
        Log.e('Error deleting folder: $e');
      }
    }

    // FIXME: what if we receive a new video/thumbnail right here, when the videos directory doesn't exist?

    // Create the (empty) videos directory again
    try {
      await videoDir.create(recursive: true);
    } catch (e) {
      Log.e("Error: Failed to create directory for videos");
    }

    final query =
        _videoBox.query(Video_.camera.equals(widget.cameraName)).build();
    final videosToDelete = query.find();
    query.close();

    _videoBox.removeMany(videosToDelete.map((v) => v.id).toList());

    setState(() {
      _videos.clear();
      _offset = 0;
      _hasMore = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('All videos deleted.'),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );

    // nuke any residual caches
    _videoThumbCache.clear();
    _videoThumbFutures.clear();

    reloadVideos();
  }

  void _deleteOne(Video v, int index) async {
    final dir = await getApplicationDocumentsDirectory();

    if (v.received) {
      final videoPath = '${dir.path}/camera_dir_${v.camera}/videos/${v.video}';
      final file = File(videoPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          Log.e('Error deleting file: $e');
        }
      }

      final ts = _timestampFromVideo(v.video);
      if (ts != null) {
        final thumbPath =
            '${dir.path}/camera_dir_${v.camera}/videos/thumbnail_$ts.png';
        final thumb = File(thumbPath);
        if (await thumb.exists()) {
          try {
            await thumb.delete();
          } catch (_) {}
        }
      }
    }

    _invalidateVideoThumb(v.camera, v.video);
    _videoBox.remove(v.id);
    setState(() => _videos.removeAt(index));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video deleted'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String? _timestampFromVideo(String videoFile) {
    // expects "video_<unix>.mp4"
    if (!videoFile.startsWith("video_") || !videoFile.endsWith(".mp4"))
      return null;
    return videoFile.substring(
      6,
      videoFile.length - 4,
    ); // strip "video_" and ".mp4"
  }

  Future<String?> _findPngForVideo(String cameraName, String videoFile) async {
    final ts = _timestampFromVideo(videoFile);
    if (ts == null) return null;

    final docs = await getApplicationDocumentsDirectory();
    final path = "${docs.path}/camera_dir_$cameraName/videos/thumbnail_$ts.png";
    final f = File(path);
    return await f.exists() ? path : null;
  }

  Future<Uint8List?> _loadVideoThumbBytes(String cameraName, String videoFile) {
    final ts = _timestampFromVideo(videoFile);
    if (ts == null) return Future.value(null);
    final key = "$cameraName/$ts";

    if (_videoThumbCache.containsKey(key)) {
      return Future.value(_videoThumbCache[key]);
    }
    if (_videoThumbFutures.containsKey(key)) {
      return _videoThumbFutures[key]!;
    }

    final fut = () async {
      try {
        final path = await _findPngForVideo(cameraName, videoFile);
        if (path == null) {
          _videoThumbCache[key] = null; // remember miss
          return null;
        }
        final bytes = await File(path).readAsBytes();
        _videoThumbCache[key] = bytes;
        return bytes;
      } catch (e) {
        Log.e("Video thumb load error [$key]: $e");
        _videoThumbCache[key] = null;
        return null;
      } finally {
        _videoThumbFutures.remove(key);
      }
    }();

    _videoThumbFutures[key] = fut;
    return fut;
  }

  void _invalidateVideoThumb(String cameraName, String videoFile) {
    final ts = _timestampFromVideo(videoFile);
    if (ts == null) return;
    final key = "$cameraName/$ts";
    _videoThumbCache.remove(key);
    _videoThumbFutures.remove(key);
  }

  List<Widget> _iconsForVideo(Video v) {
    final types = _detCache[v.id] ?? const <String>{};
    if (types.isEmpty) return const [];

    final icons = <IconData>[
      if (types.contains('human')) Icons.person,
      if (types.contains('vehicle')) Icons.directions_car,
      if (types.contains('pet')) Icons.pets,
    ];

    return icons
        .map(
          (i) => Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(i, size: 14, color: Colors.grey),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final dark = theme.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cameraName, style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 139, 179, 238),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(cameraName: widget.cameraName),
                  ),
                ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _primaryBtn(
                      label: 'Go Live',
                      icon: Icons.live_tv,
                      color: const Color.fromARGB(255, 139, 179, 238),
                      enabled: true,
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => LivestreamPage(
                                    cameraName: widget.cameraName,
                                  ),
                            ),
                          ),
                    ),
                    _primaryBtn(
                      label: 'Delete All',
                      icon: Icons.delete,
                      color: Colors.red[700]!,
                      onTap: _deleteAllVideos,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'Tap to play. Long-press to delete.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _videos.length + (_hasMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= _videos.length) {
                      // spinner row
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final v = _videos[i];
                    final videoType = v.motion ? 'Detected' : 'Livestream';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: FutureBuilder<Widget>(
                          future: _thumbPlaceholder(v.camera, v.video),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.done &&
                                snapshot.hasData) {
                              return snapshot.data!;
                            } else {
                              return const SizedBox(
                                width: 80,
                                height: 80,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        title: Text(
                          repackageVideoTitle(v.video),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              videoType,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if (v.received && v.motion) ..._iconsForVideo(v),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => VideoViewPage(
                                      cameraName: v.camera,
                                      videoTitle: v.video,
                                      visibleVideoTitle: repackageVideoTitle(
                                        v.video,
                                      ),
                                      canDownload: v.received,
                                    ),
                              ),
                            ),
                        onLongPress: () => _deleteOne(v, i),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // confetti
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: -1.57,
              emissionFrequency: 0.05,
              numberOfParticles: 30,
              gravity: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Future<Widget> _thumbPlaceholder(String cameraName, String videoFile) async {
    final bytes = await _loadVideoThumbBytes(cameraName, videoFile);

    if (bytes == null) {
      return SizedBox(
        width: 80,
        height: 80,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Colors.grey[300],
            child: const Icon(Icons.videocam, color: Colors.black54),
          ),
        ),
      );
    }

    return SizedBox(
      width: 80,
      height: 80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }

  Widget _primaryBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) => ElevatedButton(
    onPressed: enabled ? onTap : null, // Disable if not enabled
    style: ElevatedButton.styleFrom(
      backgroundColor: enabled ? color : Colors.grey[400], // Gray if disabled
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}
