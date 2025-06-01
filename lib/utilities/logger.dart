import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

class LogMessage {
  final dynamic value;
  final String customLocation;

  LogMessage(this.value, {this.customLocation = ""});
}

class Log {
  static void init() {
    _logger = Logger(
      level: kReleaseMode ? Level.warning : Level.debug,
      printer: _OneLinePrinter(debugMode: !kReleaseMode),
    );
  }

  static void d(dynamic msg, {String customLocation = ""}) => _logger.d(
    LogMessage(msg, customLocation: customLocation),
    stackTrace: StackTrace.current,
  );

  static void i(dynamic msg, {String customLocation = ""}) => _logger.i(
    LogMessage(msg, customLocation: customLocation),
    stackTrace: StackTrace.current,
  );

  static void w(dynamic msg, {String customLocation = ""}) => _logger.w(
    LogMessage(msg, customLocation: customLocation),
    stackTrace: StackTrace.current,
  );

  static void e(dynamic msg, {String customLocation = ""}) => _logger.e(
    LogMessage(msg, customLocation: customLocation),
    stackTrace: StackTrace.current,
  );

  static late final Logger _logger;
}

class _OneLinePrinter extends LogPrinter {
  _OneLinePrinter({required this.debugMode});

  final bool debugMode;

  static const _levelMap = {
    Level.trace: 'T',
    Level.debug: 'D',
    Level.info: 'I',
    Level.warning: 'W',
    Level.error: 'E',
    Level.fatal: 'F',
  };
  @override
  List<String> log(LogEvent event) {
    final _time = DateFormat('HH:mm:ss.SSS');
    final ts = _time.format(DateTime.now());
    final tag = _levelMap[event.level] ?? '?';

    dynamic actualMessage = event.message;
    dynamic customLocation = "";

    if (event.message is LogMessage) {
      final logMsg = event.message as LogMessage;
      customLocation = logMsg.customLocation;
      actualMessage = logMsg.value;
    }

    // We don't need to show line numbers in debug mode.
    final loc =
        !debugMode
            ? ""
            : (customLocation == "" ? _callerLocation() : customLocation);
    final pad = loc.isNotEmpty ? ' ' : '';

    return ['$ts [$tag] $loc$pad→ $actualMessage'];
  }

  // Grab first stack-frame outside logger / flutter internals.
  String _callerLocation() {
    final traceLines = StackTrace.current.toString().split('\n');
    for (final line in traceLines) {
      if (line.contains('.dart') &&
          !line.contains('logger.dart') &&
          !line.contains('Log.') &&
          !line.contains('package:flutter')) {
        final match = RegExp(
          r'([A-Za-z0-9_/.]+\.dart):(\d+):(\d+)',
        ).firstMatch(line);
        if (match != null) {
          return '${match.group(1)}:${match.group(2)}:${match.group(3)}';
        }
      }
    }
    return ''; // fallback – no location
  }
}
