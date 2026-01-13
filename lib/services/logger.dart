import 'package:flutter/foundation.dart';
import 'log_collector.dart';

/// Simple logger service for BLE operations
class Logger {
  static const String _prefix = '[BLE]';
  static final LogCollector _collector = LogCollector();

  static void info(String message) {
    final fullMessage = 'ℹ️  $message';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    _collector.info(message);
  }

  static void success(String message) {
    final fullMessage = '✓ $message';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    _collector.success(message);
  }

  static void error(String message, [Object? error]) {
    final fullMessage = '✗ $message${error != null ? ': $error' : ''}';
    if (kDebugMode) {
      debugPrint('$_prefix $fullMessage');
    }
    _collector.error(message);
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

