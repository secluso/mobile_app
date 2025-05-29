import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';

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
    print("found path: $_videoPath");
    _controller = VideoPlayerController.file(File(_videoPath));

    await _controller.initialize();
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
    print("Requested video download");
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
            print("Granted permission to photos");

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.visibleVideoTitle,
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_initialized)
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            else
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Detections: ${widget.detections.isNotEmpty ? widget.detections.join(', ') : 'None'}",
                style: const TextStyle(fontSize: 16),
              ),
            ),
            if (widget.canDownload)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: ElevatedButton(
                  onPressed: _downloadVideo,
                  child: const Text("Download Video"),
                ),
              ),
          ],
        ),
      ),

      floatingActionButton:
          _initialized
              ? FloatingActionButton(
                onPressed: _togglePlayPause,
                child: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              )
              : null,
    );
  }
}
