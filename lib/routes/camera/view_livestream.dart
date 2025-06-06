import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/utilities/byte_stream_player.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/utilities/rust_util.dart';
import 'package:privastead_flutter/utilities/byte_player_view.dart';
import 'package:privastead_flutter/utilities/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:privastead_flutter/database/entities.dart';
import 'package:privastead_flutter/database/app_stores.dart';
import 'package:privastead_flutter/routes/camera/view_camera.dart';
import 'dart:io';
import '../../objectbox.g.dart';

//TODO: Create iOS native code for this

class LivestreamPage extends StatefulWidget {
  final String cameraName;
  const LivestreamPage({required this.cameraName});

  @override
  State<LivestreamPage> createState() => _LivestreamPageState();
}

class _LivestreamPageState extends State<LivestreamPage>
    with WidgetsBindingObserver {
  bool isStreaming = false;
  bool hasFailed = false;
  String _errMsg = '';
  double? _aspectRatio;
  int? _streamId;
  bool _needToCreateFile = true;

  late final MethodChannel _methodChannel;
  AppLifecycleState?
  _lastLifecycleState; // Store the lifecycle state that was last to ensure we don't cancel the livestream for screen rotation

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLivestream();
  }

  @override
  void dispose() {
    _finishNativeStream();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startLivestream() async {
    Log.d('Entered method');

    final prefs = await SharedPreferences.getInstance();
    while (prefs.getBool(PrefKeys.downloadingMotionVideos) ?? false) {
      Log.d('Waiting for motion-video download to finish…');
      await Future.delayed(const Duration(seconds: 1));
    }

    for (int i = 0; i < 2; i++) {
      final startRes = await HttpClientService.instance.livestreamStart(
        widget.cameraName,
      );

      bool startSucceeded = false;
      await startRes.fold(
        (_) async {
          Log.d('Launching native player');
          try {
            _streamId = await ByteStreamPlayer.createStream();
            Log.d('Native queue id = $_streamId');
            _methodChannel = MethodChannel('byte_player_view_$_streamId');
            _methodChannel.setMethodCallHandler((call) async {
              if (call.method == 'onAspectRatio') {
                final ratio = call.arguments as double;
                Log.d("Recieved aspect ratio $ratio");
                if (ratio > 0 && mounted) {
                  setState(() {
                    _aspectRatio = ratio;
                  });
                }
              }
            });
          } catch (e) {
            _fail('Could not start native player: $e');
            return;
          }

          final cmOk = await _retrieveAndApplyCommitMsg();
          if (!cmOk) return; // error handled inside

          setState(() => isStreaming = true);
          _startChunkPump();
          startSucceeded = true;
          return;
        },
        (err) async {
          if (i == 1) {
            _fail('Failed: $err');
            return;
          }
        },
      );

      if (startSucceeded || i == 1) {
        return;
      }

      // We get here when we get an error trying to start livestream.
      // One possibility for the error is that there is a pending commit message (chunk 0)
      // from a previous failed attempt on the server.
      // In that case, we need to apply that and then try to start livestream again.
      await _tryRetrieveAndApplyCommitMSg();
    }
  }

  Future<bool> _tryRetrieveAndApplyCommitMSg() async {
    final res = await HttpClientService.instance.livestreamRetrieve(
      cameraName: widget.cameraName,
      chunkNumber: 0,
    );

    final ok = await res.fold(
      (bytes) async {
        final updated = await livestreamUpdateApi(
          cameraName: widget.cameraName,
          msg: bytes,
        );

        if (!updated) {
          _fail('Could not apply commit message');
          return false;
        }
        return true;
      },
      (err) async {
        Log.d('Commit error: $err');
        return false;
      },
    );
    if (ok) {
      Log.d('Commit applied');
      return true;
    }

    return ok;
  }

  Future<bool> _retrieveAndApplyCommitMsg() async {
    Log.d('Fetch commit msg (chunk 0)…');
    int attempt = 0;

    while (true) {
      final res = await _tryRetrieveAndApplyCommitMSg();
      if (res == true) {
        return true;
      }
      if (++attempt > 5) {
        _fail('Could not retrieve commit message after 5 retries');
        return false;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  // bytes to queue action
  Future<void> _startChunkPump() async {
    Log.d('Start chunk pump');
    int chunk = 1;
    final id = _streamId!;
    final String cameraName = widget.cameraName;
    File? _videoFile;

    while (isStreaming) {
      final res = await HttpClientService.instance.livestreamRetrieve(
        cameraName: cameraName,
        chunkNumber: chunk,
      );

      await res.fold(
        (enc) async {
          final dec = await livestreamDecryptApi(
            cameraName: cameraName,
            encData: enc,
            expectedChunkNumber: BigInt.from(chunk),
          );
          if (chunk == 1) {
            final first16 = dec
                .take(16)
                .map((b) => b.toRadixString(16).padLeft(2, '0'));
            Log.d('First 16 bytes: $first16');
          }

          await ByteStreamPlayer.push(id, dec);
          Log.d('Pushed chunk $chunk (${dec.length} B)');

          if (_needToCreateFile) {
            final baseDir = await getApplicationDocumentsDirectory();

            final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final String videoName = 'video_$timestamp.mp4';
            final filePath = p.join(
              baseDir.path,
              'camera_dir_$cameraName',
              videoName,
            );

            final parentDir = Directory(p.dirname(filePath));
            if (!await parentDir.exists()) {
              await parentDir.create(recursive: true);
            }

            _videoFile = File(filePath);
            await _videoFile!.writeAsBytes(dec, mode: FileMode.writeOnly);

            // TODO: The rest of the code here is almost identical to the code in pending_processor.dart
            final box = AppStores.instance.videoStore.box<Video>();
            var video = Video(cameraName, videoName, true, false);
            box.put(video);

            final cameraBox = AppStores.instance.cameraStore.box<Camera>();
            final cameraQuery =
                cameraBox.query(Camera_.name.equals(cameraName)).build();

            final foundCamera = cameraQuery.findFirst();
            cameraQuery.close();

            if (foundCamera == null) {
              Log.e(
                "Camera entity is null in database. This shouldn't be possible. Camera: $cameraName Video: $videoName",
              );
            } else {
              // Skip saving unreadMessages = true as they would've seen the livestream.
              if (globalCameraViewPageState?.mounted == true &&
                  globalCameraViewPageState?.widget.cameraName == cameraName) {
                globalCameraViewPageState?.reloadVideos();
              } else if (globalCameraViewPageState?.mounted == false) {
                Log.d("Not reloading current camera page - not mounted");
              } else {
                final currentPage =
                    globalCameraViewPageState?.widget.cameraName;
                Log.d(
                  "Not reloading current camera page - name doesn't match. $currentPage, $cameraName",
                );
              }
            }

            _needToCreateFile = false;
          } else {
            if (_videoFile != null) {
              await _videoFile!.writeAsBytes(
                dec,
                mode: FileMode.writeOnlyAppend,
              );
            } else {
              // Should not happen
              Log.d('Livestream video file not created');
            }
          }

          chunk++;
        },
        (err) async {
          Log.d('Chunk $chunk error: $err');
          // TODO: At some point, we should stop trying to find more chunks... show user an error. Also, what if a user closes out of the page? This continues on.
        },
      );

      await Future.delayed(const Duration(milliseconds: 300));
    }

    Log.d('Pump exited');
  }

  //finish / error
  Future<void> _finishNativeStream() async {
    final id = _streamId;
    if (id != null) {
      await ByteStreamPlayer.push(id, Uint8List(0)); // EOF
      await ByteStreamPlayer.finish(id);

      await HttpClientService.instance.livestreamEnd(widget.cameraName);

      Log.d('Completed method');
    }
  }

  void _fail(String msg) {
    Log.e('Livestream fail - $msg');
    setState(() {
      hasFailed = true;
      _errMsg = msg;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    Log.i("Changed state to ${state.name}");
    if (_lastLifecycleState != null) {
      Log.i("last state was ${_lastLifecycleState!.name}");
    }

    if (state == AppLifecycleState.resumed) {
      Log.i("App Lifecycle State set to RESUMED within livestream");

      // Only pop if last state was in background (not screen rotation)
      if (_lastLifecycleState == AppLifecycleState.paused ||
          _lastLifecycleState == AppLifecycleState.hidden) {
        if (mounted) {
          setState(() => isStreaming = false);
          Navigator.pop(context);
        }
      }
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (mounted) {
        setState(() => isStreaming = false);
      }
    }

    _lastLifecycleState = state;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      appBar:
          isLandscape
              ? null
              : AppBar(
                leading: IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: () {
                    Log.i("Back button pressed");
                    setState(() => isStreaming = false);
                    Navigator.pop(context);
                  },
                ),
                title: Text(
                  'Livestream - ${widget.cameraName}',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: const Color.fromARGB(255, 27, 114, 60),
                iconTheme: const IconThemeData(color: Colors.white),
              ),
      body:
          hasFailed
              ? Center(
                child: Text(
                  'Failed:\n$_errMsg',
                  style: const TextStyle(color: Colors.red, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              )
              : isStreaming
              ? LayoutBuilder(
                builder: (context, constraints) {
                  final ratio =
                      _aspectRatio ?? 16 / 9; // Default fallback ratio

                  final screenWidth = constraints.maxWidth;
                  final screenHeight = constraints.maxHeight;

                  double videoWidth = screenWidth;
                  double videoHeight = videoWidth / ratio;

                  if (videoHeight > screenHeight) {
                    videoHeight = screenHeight;
                    videoWidth = videoHeight * ratio;
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: videoWidth,
                        height: videoHeight,
                        child: BytePlayerView(streamId: _streamId!),
                      ),
                      Positioned(
                        bottom: 24,
                        child: const Text(
                          'Live',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  );
                },
              )
              : const Center(child: CircularProgressIndicator()),

      floatingActionButton:
          isStreaming
              ? FloatingActionButton(
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.stop),
                onPressed: () {
                  setState(() => isStreaming = false);
                  Navigator.pop(context);
                },
              )
              : null,
    );
  }
}
