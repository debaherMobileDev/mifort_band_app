import 'package:flutter/foundation.dart';
import 'log_collector.dart';

/// Simple logger service for BLE operations
class Logger {
  static const String _prefix = '[BLE]';
  static final LogCollector _collector = LogCollector();

  static void info(String message, {bool pinned = false}) {
    final fullMessage = 'ℹ️  $message';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    if (pinned) {
      _collector.pinnedInfo(message);
    } else {
      _collector.info(message);
    }
  }

  static void success(String message, {bool pinned = false}) {
    final fullMessage = '✓ $message';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    if (pinned) {
      _collector.pinnedSuccess(message);
    } else {
      _collector.success(message);
    }
  }

  static void error(String message, [Object? error, bool pinned = false]) {
    final fullMessage = '✗ $message${error != null ? ': $error' : ''}';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    if (pinned) {
      _collector.pinnedError(message);
    } else {
      _collector.error(message);
    }
  }

  static void warning(String message) {
    final fullMessage = '⚠️  $message';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    _collector.warning(message);
  }

  static void debug(String message) {
    final fullMessage = '🔍 $message';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    _collector.debug(message);
  }
}

