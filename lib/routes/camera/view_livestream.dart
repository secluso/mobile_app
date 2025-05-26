import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:privastead_flutter/keys.dart';
import 'package:privastead_flutter/utilities/byte_stream_player.dart';
import 'package:privastead_flutter/utilities/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:privastead_flutter/utilities/camera_util.dart';
import 'package:privastead_flutter/utilities/byte_player_view.dart';

//TODO: Create iOS native code for this as well

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

  int? _streamId;

  @override
  void initState() {
    super.initState();
    _startLivestream();
  }

  @override
  void dispose() {
    _finishNativeStream();
    super.dispose();
  }

  Future<void> _startLivestream() async {
    debugPrint('[LS] startLivestream()');

    final prefs = await SharedPreferences.getInstance();
    while (prefs.getBool(PrefKeys.downloadingMotionVideos) ?? false) {
      debugPrint('[LS] waiting for motion-video download to finish…');
      await Future.delayed(const Duration(seconds: 1));
    }

    final startRes = await HttpClientService.instance.livestreamStart(
      widget.cameraName,
    );

    await startRes.fold(
      (_) async {
        debugPrint('[LS] livestreamStart OK – launching native player');
        try {
          _streamId = await ByteStreamPlayer.createStream();

          debugPrint('[LS] native queue id = $_streamId');
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
        _fail('livestreamStart failed: $err');
      },
    );
  }

  Future<bool> _retrieveAndApplyCommitMsg() async {
    debugPrint('[LS] fetch commit msg (chunk 0)…');
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

          return updated;
        },
        (err) async {
          debugPrint('[LS] commit attempt $attempt error: $err');
          return false;
        },
      );
      if (ok) {
        debugPrint('[LS] commit applied');
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
    debugPrint('[LS] start chunk pump');
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
            expectedChunkNumber: chunk,
          );
          if (chunk == 1) {
            final first16 = dec
                .take(16)
                .map((b) => b.toRadixString(16).padLeft(2, '0'));
            debugPrint('[LS] first 16 bytes: $first16');
          }

          await ByteStreamPlayer.push(id, dec);
          debugPrint('[LS] pushed chunk $chunk (${dec.length} B)');
          chunk++;
        },
        (err) async {
          debugPrint('[LS] chunk $chunk error: $err');
          // TODO: At some point, we should stop trying to find more chunks... show user an error. Also, what if a user closes out of the page? This continues on.
        },
      );

      await Future.delayed(const Duration(milliseconds: 300));
    }

    debugPrint('[LS] pump exited');
  }

  //finish / error
  Future<void> _finishNativeStream() async {
    final id = _streamId;
    if (id != null) {
      await ByteStreamPlayer.push(id, Uint8List(0)); // EOF
      await ByteStreamPlayer.finish(id);
      debugPrint('[LS] finishNativeStream complete');

      // TODO: Save the video to the database
    }
  }

  void _fail(String msg) {
    debugPrint('[LS] fail - $msg');
    setState(() {
      hasFailed = true;
      _errMsg = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Livestream - ${widget.cameraName}'),
        backgroundColor: const Color.fromARGB(255, 27, 114, 60),
      ),
      body: Center(
        child:
            hasFailed
                ? Text(
                  'Failed:\n$_errMsg',
                  style: const TextStyle(color: Colors.red, fontSize: 15),
                  textAlign: TextAlign.center,
                )
                : isStreaming
                ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Native player
                    SizedBox(
                      width: 320,
                      height: 180,
                      child: Container(
                        width: 320,
                        height: 180,
                        child: BytePlayerView(streamId: _streamId!),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Live', style: TextStyle(color: Colors.white)),
                  ],
                )
                : const CircularProgressIndicator(),
      ),
      floatingActionButton:
          isStreaming
              ? FloatingActionButton(
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.stop),
                onPressed: () {
                  setState(() => isStreaming = false);
                  _finishNativeStream();
                  Navigator.pop(context);
                },
              )
              : null,
    );
  }
}
