import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/utilities/byte_stream_player.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/utilities/camera_util.dart';
import 'package:privastead_flutter/utilities/byte_player_view.dart';
import 'package:privastead_flutter/utilities/logger.dart';

//TODO: Create iOS native code for this

class LivestreamPage extends StatefulWidget {
  final String cameraName;
  const LivestreamPage({required this.cameraName});

  @override
  State<LivestreamPage> createState() => _LivestreamPageState();
}

class _LivestreamPageState extends State<LivestreamPage> {
  bool isStreaming = false;
  bool hasFailed = false;
  String _errMsg = '';
  double? _aspectRatio;

  int? _streamId;

  @override
  void initState() {
    super.initState();
    _startLivestream();
    _fetchAspectRatio();
  }

  @override
  void dispose() {
    _finishNativeStream();
    super.dispose();
  }

  Future<void> _fetchAspectRatio() async {
    //TODO: get the actual width and height from the native player and set the right aspect ratio
    setState(() {
      _aspectRatio = 16 / 9;
    });
  }

  Future<void> _startLivestream() async {
    Log.d('Entered method');

    final prefs = await SharedPreferences.getInstance();
    while (prefs.getBool(PrefKeys.downloadingMotionVideos) ?? false) {
      Log.d('Waiting for motion-video download to finish…');
      await Future.delayed(const Duration(seconds: 1));
    }

    final startRes = await HttpClientService.instance.livestreamStart(
      widget.cameraName,
    );

    await startRes.fold(
      (_) async {
        Log.d('Launching native player');
        try {
          _streamId = await ByteStreamPlayer.createStream();

          Log.d('Native queue id = $_streamId');
        } catch (e) {
          _fail('Could not start native player: $e');
          return;
        }

        final cmOk = await _retrieveAndApplyCommitMsg();
        if (!cmOk) return; // error handled inside

        setState(() => isStreaming = true);
        _startChunkPump();
      },
      (err) async {
        _fail('Failed: $err');
      },
    );
  }

  Future<bool> _retrieveAndApplyCommitMsg() async {
    Log.d('Fetch commit msg (chunk 0)…');
    int attempt = 0;

    while (true) {
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
          }
          return true;
        },
        (err) async {
          Log.d('Commit attempt $attempt error: $err');
          return false;
        },
      );
      if (ok) {
        Log.d('Commit applied');
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

    while (isStreaming) {
      final res = await HttpClientService.instance.livestreamRetrieve(
        cameraName: widget.cameraName,
        chunkNumber: chunk,
      );

      await res.fold(
        (enc) async {
          final dec = await livestreamDecryptApi(
            cameraName: widget.cameraName,
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

      // TODO: Save the video to the database
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Livestream - ${widget.cameraName}',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: hasFailed
            ? Text(
                'Failed:\n$_errMsg',
                style: const TextStyle(color: Colors.red, fontSize: 15),
                textAlign: TextAlign.center,
              )
            : isStreaming
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_aspectRatio != null)
                        AspectRatio(
                          aspectRatio: _aspectRatio!,
                          child: BytePlayerView(streamId: _streamId!),
                        )
                      else
                        const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('Live', style: TextStyle(color: Colors.white)),
                    ],
                  )
                : const CircularProgressIndicator(),
      ),
      floatingActionButton: isStreaming
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
