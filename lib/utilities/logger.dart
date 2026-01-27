//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secluso_flutter/utilities/trace_id.dart';

class LogMessage {
  final dynamic value;
  final String customLocation;

  LogMessage(this.value, {this.customLocation = ""});
}

class BackgroundLogSnapshot {
  final String logs;
  final String reason;
  final DateTime? timestamp;

  BackgroundLogSnapshot(this.logs, {required this.reason, this.timestamp});
}

class Log {
  static const int _maxEntries = 300;
  static const String _prefsKey = 'log_buffer';
  static const String _prefsErrorKey = 'log_error_ts';
  static const String _prefsBackgroundKey = 'log_background_snapshot';
  static const String _prefsBackgroundReasonKey = 'log_background_reason';
  static const String _prefsBackgroundTsKey = 'log_background_ts';

  static final ValueNotifier<int> errorNotifier = ValueNotifier(0);

  static final Object _contextKey = Object();
  static String _defaultContext = '';

  static void init() {
    _logger = _buildLogger();
  }

  static void setDefaultContext(String context) {
    _defaultContext = context;
  }

  static String deriveContext(String prefix) {
    final base = currentContextId();
    final child = newTraceId(prefix);
    return base.isEmpty ? child : '$base/$child';
  }

  static Logger _buildLogger() => Logger(
    level: kReleaseMode ? Level.warning : Level.debug,
    printer: _OneLinePrinter(debugMode: !kReleaseMode),
  );

  static Logger _ensureLogger() => _logger ??= _buildLogger();

  // Attach a trace tag to the current async chain so all Log.* calls inside
  // that flow carry the same origin label, without threading IDs through every
  // function signature.
  static Future<T> runWithContext<T>(
    String context,
    Future<T> Function() action,
  ) {
    return runZoned(
      action,
      zoneValues: {_contextKey: context},
    );
  }

  static Future<T> runWithDerivedContext<T>(
    String prefix,
    Future<T> Function() action,
  ) {
    final context = deriveContext(prefix);
    return runWithContext(context, action);
  }

  static T runWithContextSync<T>(String context, T Function() action) {
    return runZoned(
      action,
      zoneValues: {_contextKey: context},
    );
  }

  static T runWithDerivedContextSync<T>(
    String prefix,
    T Function() action,
  ) {
    final context = deriveContext(prefix);
    return runWithContextSync(context, action);
  }

  static String _contextTag() {
    final context = Zone.current[_contextKey] as String?;
    final effective = context == null || context.isEmpty ? _defaultContext : context;
    return effective.isEmpty ? '' : '[$effective] ';
  }

  static String currentContextId() {
    final context = Zone.current[_contextKey] as String?;
    if (context != null && context.isNotEmpty) return context;
    return _defaultContext;
  }

  static String ownerTag() {
    final context = currentContextId();
    return 'owner=${context.isNotEmpty ? context : 'unknown'}';
  }

  static String _stripPathPrefix(String loc) {
    const prefix = 'secluso_flutter/';
    if (loc.startsWith(prefix)) {
      return loc.substring(prefix.length);
    }
    return loc;
  }

  static void d(dynamic msg, {String customLocation = ""}) {
    _record(Level.debug, msg, customLocation: customLocation);
    _ensureLogger().d(
      LogMessage(msg, customLocation: customLocation),
      stackTrace: StackTrace.current,
    );
  }

  static void i(dynamic msg, {String customLocation = ""}) {
    _record(Level.info, msg, customLocation: customLocation);
    _ensureLogger().i(
      LogMessage(msg, customLocation: customLocation),
      stackTrace: StackTrace.current,
    );
  }

  static void w(dynamic msg, {String customLocation = ""}) {
    _record(Level.warning, msg, customLocation: customLocation);
    _ensureLogger().w(
      LogMessage(msg, customLocation: customLocation),
      stackTrace: StackTrace.current,
    );
  }

  static void e(dynamic msg, {String customLocation = ""}) {
    _record(Level.error, msg, customLocation: customLocation);
    _ensureLogger().e(
      LogMessage(msg, customLocation: customLocation),
      stackTrace: StackTrace.current,
    );
  }

  static Future<void> ensureStorageReady() async {
    if (_storageReady || _loadingStorage) return;
    _loadingStorage = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_prefsKey);
      if (stored != null && stored.isNotEmpty) {
        _buffer = List<String>.from(stored);
        if (_buffer.length > _maxEntries) {
          _buffer = _buffer.sublist(_buffer.length - _maxEntries);
        }
      }
      _lastErrorEpochMs = prefs.getInt(_prefsErrorKey) ?? 0;
      _storageReady = true;
    } catch (_) {
      // Ignore; storage will be retried on next flush.
    } finally {
      _loadingStorage = false;
    }
  }

  static Future<String> getLogDump() async {
    await ensureStorageReady();
    return _buffer.join('\n');
  }

  static Future<void> saveBackgroundSnapshot({
    String reason = '',
  }) async {
    await ensureStorageReady();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBackgroundKey, _buffer.join('\n'));
    if (reason.isNotEmpty) {
      await prefs.setString(_prefsBackgroundReasonKey, reason);
    } else {
      await prefs.remove(_prefsBackgroundReasonKey);
    }
    await prefs.setInt(
      _prefsBackgroundTsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<BackgroundLogSnapshot?> getBackgroundSnapshot() async {
    await ensureStorageReady();
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_prefsBackgroundKey);
    if (data == null || data.trim().isEmpty) return null;
    final reason = prefs.getString(_prefsBackgroundReasonKey) ?? '';
    final ts = prefs.getInt(_prefsBackgroundTsKey);
    final when =
        ts == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ts, isUtc: false);
    return BackgroundLogSnapshot(data, reason: reason, timestamp: when);
  }

  static Future<void> clearBackgroundSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsBackgroundKey);
      await prefs.remove(_prefsBackgroundReasonKey);
      await prefs.remove(_prefsBackgroundTsKey);
    } catch (_) {}
  }

  static Future<bool> hasRecentError() async {
    await ensureStorageReady();
    return _lastErrorEpochMs != 0;
  }

  static Future<void> clearErrorFlag() async {
    _lastErrorEpochMs = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsErrorKey);
    } catch (_) {}
  }

  static Logger? _logger;
  static List<String> _buffer = [];
  static Timer? _flushTimer;
  static bool _storageReady = false;
  static bool _loadingStorage = false;
  static int _lastErrorEpochMs = 0;

  static const Map<Level, String> _levelMap = {
    Level.trace: 'T',
    Level.debug: 'D',
    Level.info: 'I',
    Level.warning: 'W',
    Level.error: 'E',
    Level.fatal: 'F',
  };

  static void _record(
    Level level,
    dynamic msg, {
    String customLocation = "",
  }) {
    final line = _formatLine(
      level,
      msg,
      customLocation: customLocation,
    );
    _appendLine(line);

    if (level == Level.error || level == Level.fatal) {
      _lastErrorEpochMs = DateTime.now().millisecondsSinceEpoch;
      errorNotifier.value++;

      final marker = _formatLine(
        Level.warning,
        'UI error banner flagged',
        customLocation: 'logger.dart:errflag',
      );
      _appendLine(marker);

      // Emit a visible marker in stdout without re-entering _record.
      _ensureLogger().w(
        LogMessage(
          'UI error banner flagged',
          customLocation: 'logger.dart:errflag',
        ),
        stackTrace: StackTrace.current,
      );
    }

    _scheduleFlush();
  }

  static void _appendLine(String line) {
    _buffer.add(line);
    if (_buffer.length > _maxEntries) {
      _buffer.removeRange(0, _buffer.length - _maxEntries);
    }
  }

  static String _formatLine(
    Level level,
    dynamic msg, {
    String customLocation = "",
  }) {
    final ts = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final tag = _levelMap[level] ?? '?';
    final rawLoc =
        customLocation.isNotEmpty ? customLocation : _callerLocation();
    final loc = rawLoc.isNotEmpty ? _stripPathPrefix(rawLoc) : rawLoc;
    final pad = loc.isNotEmpty ? ' ' : '';
    final ctx = _contextTag();
    return '$ts [$tag] $loc$pad→ $ctx$msg';
  }

  static String _callerLocation() {
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
          final raw = '${match.group(1)}:${match.group(2)}:${match.group(3)}';
          return _stripPathPrefix(raw);
        }
      }
    }
    return '';
  }

  static void _scheduleFlush() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(seconds: 1), () async {
      _flushTimer = null;
      try {
        await _writeToPrefs();
      } catch (_) {}
    });
  }

  static Future<void> _writeToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _buffer);
      if (_lastErrorEpochMs != 0) {
        await prefs.setInt(_prefsErrorKey, _lastErrorEpochMs);
      }
      _storageReady = true;
    } catch (_) {
      // Ignore; will retry on next flush.
    }
  }
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
            : (customLocation == ""
                ? _callerLocation()
                : Log._stripPathPrefix(customLocation));
    final pad = loc.isNotEmpty ? ' ' : '';
    final ctx = Log._contextTag();
    return ['$ts [$tag] $loc$pad→ $ctx$actualMessage'];
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
          final raw = '${match.group(1)}:${match.group(2)}:${match.group(3)}';
          return Log._stripPathPrefix(raw);
        }
      }
    }
    return ''; // fallback – no location
  }
}
