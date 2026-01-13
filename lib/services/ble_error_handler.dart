import 'package:flutter/material.dart';
import 'logger.dart';

/// BLE Error types
enum BleErrorType {
  connectionFailed,
  serviceNotFound,
  characteristicNotFound,
  commandTimeout,
  commandFailed,
  parsingError,
  deviceNotReady,
  invalidResponse,
  permissionDenied,
  bluetoothOff,
  unknown,
}

/// BLE Error with context
class BleError {
  final BleErrorType type;
  final String message;
  final Object? originalError;
  final DateTime timestamp;

  BleError({
    required this.type,
    required this.message,
    this.originalError,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'BleError(type: $type, message: $message, error: $originalError)';
  }

  /// Get user-friendly error message
  String getUserMessage() {
    switch (type) {
      case BleErrorType.connectionFailed:
        return 'Failed to connect to device. Please try again.';
      case BleErrorType.serviceNotFound:
        return 'Muse v3 service not found. Make sure you\'re connecting to the correct device.';
      case BleErrorType.characteristicNotFound:
        return 'Device characteristics not found. The device may not be compatible.';
      case BleErrorType.commandTimeout:
        return 'Command timeout. Device did not respond in time. Try moving closer.';
      case BleErrorType.commandFailed:
        return 'Command failed. Device returned an error.';
      case BleErrorType.parsingError:
        return 'Error parsing device data. This may indicate a firmware issue.';
      case BleErrorType.deviceNotReady:
        return 'Device is not ready. Please wait and try again.';
      case BleErrorType.invalidResponse:
        return 'Invalid response from device. Try reconnecting.';
      case BleErrorType.permissionDenied:
        return 'Bluetooth permission denied. Please enable permissions in Settings.';
      case BleErrorType.bluetoothOff:
        return 'Bluetooth is turned off. Please enable Bluetooth.';
      case BleErrorType.unknown:
        return message;
    }
  }

  /// Get icon for error type
  IconData getIcon() {
    switch (type) {
      case BleErrorType.connectionFailed:
        return Icons.bluetooth_disabled;
      case BleErrorType.serviceNotFound:
      case BleErrorType.characteristicNotFound:
        return Icons.device_unknown;
      case BleErrorType.commandTimeout:
        return Icons.schedule;
      case BleErrorType.commandFailed:
      case BleErrorType.invalidResponse:
        return Icons.error_outline;
      case BleErrorType.parsingError:
        return Icons.broken_image;
      case BleErrorType.deviceNotReady:
        return Icons.hourglass_empty;
      case BleErrorType.permissionDenied:
        return Icons.block;
      case BleErrorType.bluetoothOff:
        return Icons.bluetooth_disabled;
      case BleErrorType.unknown:
        return Icons.warning;
    }
  }
}

/// Error handler with logging and UI notifications
class BleErrorHandler {
  /// Handle error with logging
  static void handleError(BleError error) {
    Logger.error(error.message, error.originalError);
  }

  /// Show error in UI (DISABLED - только логирование)
  static void showErrorSnackBar(BuildContext context, BleError error) {
    // SnackBar отключен по запросу пользователя
    // Только логирование
    handleError(error);
  }

  /// Show error dialog with details
  static void showErrorDialog(BuildContext context, BleError error) {
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(error.getIcon(), color: Colors.red),
            const SizedBox(width: 12),
            const Text('Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error.getUserMessage()),
            if (error.originalError != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Technical details:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                error.originalError.toString(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

