import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ByteStreamPlayer {
  // Platform-specific MethodChannel
  static final MethodChannel _ch = MethodChannel(
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'secluso.com/ios/byte_player'
        : 'secluso.com/android/byte_player',
  );

  /// Allocate a native byte queue and return its id.
  static Future<int> createStream() async {
    final id = await _ch.invokeMethod<int>('createStream') ?? -1;
    if (id < 0) throw Exception('Failed to create native queue');
    return id;
  }

  static Future<void> push(int id, Uint8List data) =>
      _ch.invokeMethod('pushBytes', {'id': id, 'bytes': data});

  static Future<void> finish(int id) =>
      _ch.invokeMethod('finishStream', {'id': id});

  static Future<int> queueLength(int id) async =>
      await _ch.invokeMethod<int>('qLen', {'id': id}) ?? 0;
}
