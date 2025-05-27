import 'dart:typed_data';
import 'package:flutter/services.dart';

class ByteStreamPlayer {
  static const _ch = MethodChannel('privastead.com/android/byte_player');

  /// For the embedded widget
  static Future<int> createStream() async {
    final id = await _ch.invokeMethod<int>('createStream') ?? -1;
    if (id < 0) throw Exception('Failed to create native queue');
    return id;
  }

  static Future<void> push(int id, Uint8List data) =>
      _ch.invokeMethod('pushBytes', {'id': id, 'bytes': data});

  static Future<void> finish(int id) =>
      _ch.invokeMethod('finishStream', {'id': id});
}
