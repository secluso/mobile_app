import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import 'package:privastead_flutter/utilities/logger.dart';

class VideoViewPage extends StatefulWidget {
  final String videoTitle;
  final String visibleVideoTitle;
  final List<String> detections;
  final bool canDownload;
  final String cameraName;

  const VideoViewPage({
    Key? key,
    required this.videoTitle,
    required this.visibleVideoTitle,
    required this.detections,
    required this.canDownload,
    required this.cameraName,
  }) : super(key: key);

  @override
  State<VideoViewPage> createState() => _VideoViewPageState();
}

class _VideoViewPageState extends State<VideoViewPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  late String _videoPath;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final dir = await getApplicationDocumentsDirectory();
    var cam = widget.cameraName;
    _videoPath = p.join(dir.path, "camera_dir_$cam", widget.videoTitle);
    Log.d("Found path: $_videoPath");
    _controller = VideoPlayerController.file(File(_videoPath));

    await _controller.initialize();
    await _controller.setLooping(true);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.play();
    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _downloadVideo() async {
    Log.d("Requested video download");
    final videoFile = File(_videoPath);
    if (!await videoFile.exists()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Video file not found")));
      return;
    }

    try {
      await Permission.mediaLibrary
          .onDeniedCallback(() {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Unable to save due to denied access to photos'),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
              ),
            );
          })
          .onGrantedCallback(() async {
            Log.d("Granted permission to photos");

            try {
              await Gal.putVideo(videoFile.path);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Saved to Photos")));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Unable to save for unknown reason'),
                  backgroundColor: Colors.red[700],
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          })
          .onPermanentlyDeniedCallback(() {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Unable to save due to permanently denied access to photos',
                ),
                backgroundColor: Colors.red[700],
                behavior: SnackBarBehavior.floating,
              ),
            );
          })
          .onRestrictedCallback(() {})
          .onLimitedCallback(() {})
          .onProvisionalCallback(() {})
          .request();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _togglePlayPause() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: isLandscape
          ? null
          : AppBar(
              title: Text(
                widget.visibleVideoTitle,
                style: const TextStyle(color: Colors.white),
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              backgroundColor: const Color.fromARGB(255, 27, 114, 60),
            ),
      body: _initialized
          ? isLandscape
              ? _buildLandscapePlayer()
              : _buildPortraitContent()
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildLandscapePlayer() {
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
        ),
        // Progress bar & time
        Positioned(
          left: 16,
          right: 16,
          bottom: 80,
          child: Column(
            children: [
              VideoProgressIndicator(
                _controller,
                allowScrubbing: false,
                colors: const VideoProgressColors(
                  playedColor: Color.fromARGB(255, 27, 114, 60),
                ),
                padding: const EdgeInsets.symmetric(vertical: 4),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_controller.value.position),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  Text(
                    _formatDuration(_controller.value.duration),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Playback controls
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_5),
                  iconSize: 36,
                  color: Colors.white,
                  onPressed: () {
                    final current = _controller.value.position;
                    final newPosition = current - const Duration(seconds: 5);
                    _controller.seekTo(
                      newPosition >= Duration.zero ? newPosition : Duration.zero,
                    );
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: Icon(
                    _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  iconSize: 44,
                  color: Colors.white,
                  onPressed: _togglePlayPause,
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(Icons.forward_5),
                  iconSize: 36,
                  color: Colors.white,
                  onPressed: () {
                    final current = _controller.value.position;
                    final max = _controller.value.duration;
                    final newPosition = current + const Duration(seconds: 5);
                    _controller.seekTo(newPosition <= max ? newPosition : max);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  VideoProgressIndicator(
                    _controller,
                    colors: const VideoProgressColors(
                      playedColor: Color.fromARGB(255, 27, 114, 60),
                    ),
                    allowScrubbing: false,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_controller.value.position),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        _formatDuration(_controller.value.duration),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_5),
                        iconSize: 36,
                        onPressed: () {
                          final current = _controller.value.position;
                          final newPosition = current - const Duration(seconds: 5);
                          _controller.seekTo(
                            newPosition >= Duration.zero ? newPosition : Duration.zero,
                          );
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                        iconSize: 44,
                        onPressed: _togglePlayPause,
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: const Icon(Icons.forward_5),
                        iconSize: 36,
                        onPressed: () {
                          final current = _controller.value.position;
                          final max = _controller.value.duration;
                          final newPosition = current + const Duration(seconds: 5);
                          _controller.seekTo(
                            newPosition <= max ? newPosition : max,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Detections: ${widget.detections.isNotEmpty ? widget.detections.join(', ') : 'None'}",
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "(Delivered end-to-end encrypted from the camera)",
                style: const TextStyle(fontSize: 16),
              ),
            ),
            if (widget.canDownload)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: ElevatedButton(
                  onPressed: _downloadVideo,
                  child: const Text("Save Video to Gallery"),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration position) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(position.inMinutes.remainder(60));
    final seconds = twoDigits(position.inSeconds.remainder(60));
    return "${position.inHours > 0 ? '${twoDigits(position.inHours)}:' : ''}$minutes:$seconds";
  }
}
