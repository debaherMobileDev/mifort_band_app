import 'dart:async';

/// Collector for in-app logs display
class LogCollector {
  static final LogCollector _instance = LogCollector._internal();
  factory LogCollector() => _instance;
  LogCollector._internal();

  final List<LogEntry> _logs = [];
  final StreamController<List<LogEntry>> _logsController =
      StreamController<List<LogEntry>>.broadcast();

  Stream<List<LogEntry>> get logsStream => _logsController.stream;
  List<LogEntry> get allLogs => List.unmodifiable(_logs);

  void add(String level, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );
    
    _logs.add(entry);
    
    // Keep only last 500 logs
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    
    _logsController.add(_logs);
  }

  void info(String message) => add('INFO', message);
  void success(String message) => add('SUCCESS', message);
  void error(String message) => add('ERROR', message);
  void warning(String message) => add('WARNING', message);
  void debug(String message) => add('DEBUG', message);

  void clear() {
    _logs.clear();
    _logsController.add(_logs);
  }

  String getAllLogsAsText() {
    return _logs.map((log) => log.toString()).join('\n');
  }

  void dispose() {
    _logsController.close();
  }
}

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    return '[$timeFormatted] [$level] $message';
  }
}

