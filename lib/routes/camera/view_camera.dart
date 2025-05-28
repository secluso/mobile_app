import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:objectbox/objectbox.dart';

import '../theme_provider.dart';
import 'view_video.dart';
import 'view_livestream.dart';
import 'camera_settings.dart';
import '../../objectbox.g.dart';
import 'package:privastead_flutter/database/entities.dart';
import 'package:path_provider/path_provider.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'dart:io';

_CameraViewPageState? globalCameraViewPageState;

class CameraViewPage extends StatefulWidget {
  final String cameraName;
  const CameraViewPage({super.key, required this.cameraName});

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

class _CameraViewPageState extends State<CameraViewPage> {
  late Box<Video> _videoBox;
  final List<Video> _videos = [];

  final _ch = MethodChannel('privastead.com/thumbnail');

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
    _markCameraRead();
    _initDbAndFirstPage();
    globalCameraViewPageState = this;
    _scrollController.addListener(_maybeLoadNextPage);
  }

  Future<void> _initDbAndFirstPage() async {
    _videoBox = AppStores.instance.videoStore.box<Video>();
    await _loadNextPage(); // first 20
  }

  @override
  void dispose() {
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
          ..limit = _offset;

    final newVideos = query.find();
    query.close();

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

  void _deleteAllVideos() async {
    HapticFeedback.heavyImpact();
    _confetti.play();

    // Query all videos for this camera
    final query =
        _videoBox.query(Video_.camera.equals(widget.cameraName)).build();
    final videosToDelete = query.find();
    query.close();

    final dir = await getApplicationDocumentsDirectory();

    for (final v in videosToDelete) {
      if (v.received) {
        final videoPath = '${dir.path}/camera_dir_${v.camera}/${v.video}';
        final file = File(videoPath);
        if (await file.exists()) {
          try {
            await file.delete();
            print('Deleted video file: $videoPath');
          } catch (e) {
            print('Error deleting file $videoPath: $e');
          }
        }
      }
    }

    // Bulk delete all matching from DB
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
  }

  void _deleteOne(Video v, int index) async {
    if (v.received) {
      print("Deleting video file from documents");
      final dir = await getApplicationDocumentsDirectory();
      final videoPath = '${dir.path}/camera_dir_${v.camera}/${v.video}';
      final file = File(videoPath);

      if (await file.exists()) {
        try {
          await file.delete();
          print('Deleted video file: $videoPath');
        } catch (e) {
          print('Error deleting file: $e');
        }
      } else {
        print('Video file not found: $videoPath');
      }
    }

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

  IconData? _detectionIcon(String d) =>
      {
        'human': Icons.person,
        'vehicle': Icons.directions_car,
        'pet': Icons.pets,
        'pets': Icons.pets,
      }[d.toLowerCase()];

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final dark = theme.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cameraName, style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
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
                      color: const Color.fromARGB(255, 27, 114, 60),
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
                    final status = v.received ? 'Received' : 'Pending';

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
                          v.video,
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
                              'Status: $status',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if (v.received && v.motion) ...[
                              const SizedBox(width: 8),
                              Icon(
                                _detectionIcon('human'),
                                size: 14,
                                color: Colors.grey,
                              ),
                            ],
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
                                      detections:
                                          v.motion && v.received
                                              ? ['Human']
                                              : [],
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
    if (Platform.isAndroid) {
      // For android, I skipped the thumbnail generation due to replacement of this mechanism with a frame from the camera's internal sent separately going to be used in the future
      print("Returning android placeholder");
      return SizedBox(
        width: 80,
        height: 80,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const Image(
            image: AssetImage('assets/android_thumbnail_placeholder.jpeg'),
          ),
        ),
      );
    }

    final fullVideoPath =
        (await getApplicationDocumentsDirectory()).path +
        "/camera_dir_" +
        cameraName +
        "/" +
        videoFile;

    print("Full video path: $fullVideoPath");

    final file = File(fullVideoPath);
    if (!await file.exists()) {
      return Container(
        width: 80,
        height: 80,
        color: Colors.grey,
        child: const Icon(Icons.videocam_off),
      );
    }

    print("[Thumbnail] Generating thumbnail... 2");

    var thumbnailData = null;
    try {
      // Send request to iOS native code to generate thumbnail (due to lack of good Flutter option)
      Uint8List? bytes = await _ch.invokeMethod<Uint8List>(
        'generateThumbnail',
        {'path': fullVideoPath, 'fullSize': false},
      );
      thumbnailData = bytes!;
    } on PlatformException catch (e) {
      debugPrint('Thumbnail error: ${e.code} – ${e.message}');
    }

    print("[Thumbnail] Done generating thumbnail");

    return SizedBox(
      width: 80,
      height: 80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child:
            thumbnailData != null
                ? Image.memory(thumbnailData, fit: BoxFit.cover)
                : Container(color: Colors.grey[300]),
      ),
    );
  }

  Widget _primaryBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) => ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: onTap,
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
