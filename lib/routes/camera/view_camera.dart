//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:secluso_flutter/constants.dart';
import 'package:secluso_flutter/keys.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:objectbox/objectbox.dart';
import 'package:secluso_flutter/notifications/download_task.dart';
import 'package:secluso_flutter/notifications/download_status.dart';
import 'package:secluso_flutter/notifications/thumbnails.dart';
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
import 'dart:async';
import 'dart:io';
import 'dart:ui' show decodeImageFromList;
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
  static const Duration _thumbStableWaitTimeout = Duration(seconds: 2);
  static const Duration _thumbStableWaitPoll = Duration(milliseconds: 120);
  static const int _minThumbPngSizeBytes = 32;
  static const List<int> _pngSignature = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];
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
  int _dataGeneration = 0;

  final ScrollController _scrollController = ScrollController();
  final ConfettiController _confetti = ConfettiController(
    duration: const Duration(seconds: 2),
  );
  Timer? _downloadStatusTimer;
  late final VoidCallback _downloadStatusListener;
  bool _downloadActive = false;

  /// We store an unreadMessages flag instead of iterating through all videos to be more efficient
  Future<void> _markCameraRead() async {
    if (!AppStores.isInitialized) {
      try {
        await AppStores.init();
      } catch (e, st) {
        Log.e("Failed to init AppStores: $e\n$st");
        return;
      }
    }
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
    _downloadActive = DownloadStatus.isActiveInMemory(widget.cameraName);
    _downloadStatusListener = () {
      final active = DownloadStatus.isActiveInMemory(widget.cameraName);
      if (active != _downloadActive && mounted) {
        setState(() => _downloadActive = active);
      }
    };
    DownloadStatus.active.addListener(_downloadStatusListener);
    _downloadStatusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => DownloadStatus.syncFromPrefs(),
    );
    unawaited(DownloadStatus.syncFromPrefs());
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
    if (!AppStores.isInitialized) {
      try {
        await AppStores.init();
      } catch (e, st) {
        Log.e("Failed to init AppStores: $e\n$st");
        return;
      }
    }
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
    _downloadStatusTimer?.cancel();
    DownloadStatus.active.removeListener(_downloadStatusListener);
    globalCameraViewPageState = null;

    super.dispose();
  }

  Future<void> reloadVideos() async {
    final int generation = _dataGeneration;
    final query =
        _videoBox
            .query(Video_.camera.equals(widget.cameraName))
            .order(Video_.id, flags: Order.descending)
            .build()
          ..limit = _pageSize;

    final newVideos = query.find();
    query.close();

    await _prefetchDetectionsFor(newVideos);

    if (generation != _dataGeneration || !mounted) return;
    setState(() {
      _videos.clear();
      _videos.addAll(newVideos);
      _hasMore = newVideos.length == _pageSize;
    });
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);
    final int generation = _dataGeneration;

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

    if (generation != _dataGeneration || !mounted) {
      setState(() => _isLoading = false);
      return;
    }
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
    _dataGeneration++;
    _isLoading = false;

    final dir = await getApplicationDocumentsDirectory();
    final videoDir = Directory(
      '${dir.path}/camera_dir_${widget.cameraName}/videos',
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const recentThresholdMs = 15000;
    final recentCutoffSec = ((nowMs - recentThresholdMs) / 1000).floor();

    int? newestVideoTs;
    final deletedPaths = <String>[];
    final deletedVideoNames = <String>{};
    if (await videoDir.exists()) {
      try {
        final entries = await videoDir.list(followLinks: false).toList();
        for (final entry in entries) {
          if (entry is! File) continue;
          final name = p.basename(entry.path);
          final ts = _timestampFromVideo(name);
          if (ts != null) {
            final parsed = int.tryParse(ts);
            if (parsed != null) {
              if (newestVideoTs == null || parsed > newestVideoTs!) {
                newestVideoTs = parsed;
              }
            }
          }
        }

        for (final entry in entries) {
          if (entry is! File) continue;
          final name = p.basename(entry.path);
          if (name.startsWith("thumbnail_") && name.endsWith(".png")) {
            final tsStr = name.substring("thumbnail_".length, name.length - 4);
            final ts = int.tryParse(tsStr);
            if (newestVideoTs != null && ts != null && ts > newestVideoTs!) {
              continue; // retain newer thumbnails
            }
          }
          bool shouldDelete = true;
          try {
            final stat = await entry.stat();
            if (nowMs - stat.modified.millisecondsSinceEpoch <
                recentThresholdMs) {
              shouldDelete = false; // skip very recent files
            }
          } catch (_) {}
          if (!shouldDelete) continue;
          deletedPaths.add(entry.path);
          try {
            await entry.delete();
            if (name.startsWith("video_") && name.endsWith(".mp4")) {
              deletedVideoNames.add(name);
            }
          } catch (e) {
            Log.e('Error deleting file ${entry.path}: $e');
          }
        }
        Log.d('Cleared camera folder: ${videoDir.path}');
      } catch (e) {
        Log.e('Error clearing folder: $e');
      }
    }

    // Ensure videos directory exists
    try {
      await videoDir.create(recursive: true);
    } catch (e) {
      Log.e("Error: Failed to create directory for videos");
    }

    final query =
        _videoBox.query(Video_.camera.equals(widget.cameraName)).build();
    final videosToDelete = query.find();
    query.close();

    final ids =
        videosToDelete
            .where((v) => deletedVideoNames.contains(v.video))
            .map((v) => v.id)
            .toList();
    try {
      if (ids.isNotEmpty) {
        _videoBox.removeMany(ids);
      }
    } catch (e) {
      Log.e("Error deleting videos from DB; retrying once: $e");
      try {
        if (ids.isNotEmpty) {
          _videoBox.removeMany(ids);
        }
      } catch (e2) {
        Log.e("DB delete retry failed: $e2");
      }
    }

    try {
      final countQuery =
          _videoBox.query(Video_.camera.equals(widget.cameraName)).build();
      final dbCount = countQuery.count();
      countQuery.close();

      final remainingDeletedPaths = <String>[];
      for (final path in deletedPaths) {
        if (await File(path).exists()) {
          remainingDeletedPaths.add(path);
        }
      }

      if (dbCount != 0 || remainingDeletedPaths.isNotEmpty) {
        Log.e(
          "Delete all mismatch for ${widget.cameraName}: dbCount=$dbCount remainingFiles=$remainingDeletedPaths dir=${videoDir.path}",
        );
      }
    } catch (e) {
      Log.e("Error verifying delete all for ${widget.cameraName}: $e");
    }

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
    await _logDeleteAllState(videoDir);
  }

  Future<void> _logDeleteAllState(Directory videoDir) async {
    try {
      final countQuery =
          _videoBox.query(Video_.camera.equals(widget.cameraName)).build();
      final dbCount = countQuery.count();
      final remainingVideos = countQuery.find();
      countQuery.close();

      final files = <String>[];
      final retainedThumbs = <String>[];
      int? newestVideoTs;
      if (await videoDir.exists()) {
        final entries = await videoDir.list(followLinks: false).toList();
        for (final entry in entries) {
          if (entry is! File) continue;
          final name = p.basename(entry.path);
          final ts = _timestampFromVideo(name);
          if (ts != null) {
            final parsed = int.tryParse(ts);
            if (parsed != null) {
              if (newestVideoTs == null || parsed > newestVideoTs!) {
                newestVideoTs = parsed;
              }
            }
          }
          if (entry.path.endsWith(".mp4")) {
            files.add(entry.path);
          }
        }
        if (newestVideoTs != null) {
          for (final entry in entries) {
            if (entry is! File) continue;
            final name = p.basename(entry.path);
            if (name.startsWith("thumbnail_") && name.endsWith(".png")) {
              final tsStr = name.substring(
                "thumbnail_".length,
                name.length - 4,
              );
              final ts = int.tryParse(tsStr);
              if (ts != null && ts > newestVideoTs!) {
                retainedThumbs.add(entry.path);
              }
            }
          }
        }
      }

      Log.d(
        "Delete all debug for ${widget.cameraName}: dbCount=$dbCount dbVideos=${remainingVideos.map((v) => v.video).toList()} files=$files retainedThumbs=$retainedThumbs",
      );
    } catch (e) {
      Log.e("Delete all debug failed for ${widget.cameraName}: $e");
    }
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

  Future<bool> _isValidImageBytes(Uint8List bytes) async {
    try {
      final image = await decodeImageFromList(bytes);
      image.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _looksLikePngHeader(Uint8List bytes) {
    if (bytes.length < _pngSignature.length) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  Future<bool> _waitForStablePng(String path) async {
    // Thumbnails can be created while the UI is already trying to render them.
    // We wait for a stable file size and a valid PNG header to avoid decoding
    // partially-written files that trigger image decode errors.
    final file = File(path);
    final deadline = DateTime.now().add(_thumbStableWaitTimeout);
    int? lastSize;

    while (DateTime.now().isBefore(deadline)) {
      if (!await file.exists()) return false;
      final stat = await file.stat();
      final size = stat.size;
      if (size >= _minThumbPngSizeBytes &&
          lastSize != null &&
          size == lastSize) {
        RandomAccessFile? raf;
        try {
          raf = await file.open(mode: FileMode.read);
          final header = await raf.read(_pngSignature.length);
          return _looksLikePngHeader(header);
        } catch (_) {
          return false;
        } finally {
          await raf?.close();
        }
      }
      lastSize = size;
      await Future.delayed(_thumbStableWaitPoll);
    }
    return false;
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
        final ready = await _waitForStablePng(path);
        if (!ready) {
          _videoThumbCache[key] = null;
          return null;
        }
        final bytes = await File(path).readAsBytes();
        final ok = await _isValidImageBytes(bytes);
        if (!ok) {
          Log.w("Invalid thumbnail bytes for $key; deleting $path");
          try {
            await File(path).delete();
          } catch (_) {}
          _videoThumbCache[key] = null;
          return null;
        }
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

  Future<void> _onPullToRefresh() async {
    await ThumbnailManager.retrieveThumbnails(camera: widget.cameraName);
    await retrieveVideos(widget.cameraName);
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
                  'Pull down to download missing videos (if any). Long-press to delete.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              if (_downloadActive)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          dark ? Colors.blueGrey.shade800 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            dark
                                ? Colors.blueGrey.shade600
                                : Colors.blue.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              dark ? Colors.white70 : Colors.blueAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Processing downloads...',
                            style: TextStyle(
                              fontSize: 14,
                              color: dark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _onPullToRefresh,
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
                                        isLivestream: !v.motion,
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
