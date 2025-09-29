//! SPDX-License-Identifier: GPL-3.0-or-later

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
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: 'byte_player_view',
          layoutDirection: TextDirection.ltr,
          creationParams: {'streamId': streamId},
          creationParamsCodec: const StandardMessageCodec(),
        );

      case TargetPlatform.iOS:
        return UiKitView(
          viewType: 'byte_player_view',
          layoutDirection: TextDirection.ltr,
          creationParams: {'streamId': streamId},
          creationParamsCodec: const StandardMessageCodec(),
        );

      default:
        return const Text('Live view not supported on this platform');
    }
  }
}
