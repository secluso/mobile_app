import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

class BytePlayerView extends StatelessWidget {
  final int streamId;
  const BytePlayerView({required this.streamId, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Text('Live view not supported on this platform');
    }

    return AndroidView(
      viewType: 'byte_player_view',
      layoutDirection: TextDirection.ltr,
      creationParams: <String, dynamic>{'streamId': streamId},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
