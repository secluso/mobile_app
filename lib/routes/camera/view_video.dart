import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
//import 'package:image_gallery_saver/image_gallery_saver.dart';

class VideoViewPage extends StatefulWidget {
  final String videoTitle;
  final List<String> detections;
  final bool canDownload;
  final String cameraName;

  const VideoViewPage({
    Key? key,
    required this.videoTitle,
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

    final status = await Permission.photos.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permission denied to save media")),
      );
      return;
    }

    try {
      //final bytes = await videoFile.readAsBytes();

      /**final result = await ImageGallerySaver.saveFile(videoFile.path);

      if ((result['isSuccess'] ?? false) == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Saved to Photos")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to save to Photos")),
        );
      }
      **/
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
        title: Text(widget.videoTitle),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child:
                  _initialized
                      ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                      : const CircularProgressIndicator(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Detections: ${widget.detections.isNotEmpty ? widget.detections.join(', ') : 'None'}",
              style: const TextStyle(fontSize: 16),
            ),
          ),
          if (widget.canDownload)
            ElevatedButton(
              onPressed: _downloadVideo,
              child: const Text("Download Video"),
            ),
        ],
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
