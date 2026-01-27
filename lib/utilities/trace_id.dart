//! SPDX-License-Identifier: GPL-3.0-or-later

int _lastSecond = 0;
int _perSecondCounter = 0;

String newTraceId(String prefix) {
  final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  if (nowSeconds != _lastSecond) {
    _lastSecond = nowSeconds;
    _perSecondCounter = 0;
  }
  final counter = _perSecondCounter++ % 36;
  final secondsToken = (nowSeconds % 46656).toRadixString(36).padLeft(3, '0');
  final counterToken = counter.toRadixString(36);
  return '$prefix-$secondsToken$counterToken';
}
