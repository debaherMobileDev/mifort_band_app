import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_data.dart';
import 'sensor_parser.dart';
import 'logger.dart';
import 'ble_error_handler.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _dataCharacteristic;

  final StreamController<List<ScanResult>> _scanResultsController =
      StreamController<List<ScanResult>>.broadcast();
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();
  final StreamController<List<int>> _commandResponseController =
      StreamController<List<int>>.broadcast();
  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast();
  final StreamController<BleError> _errorController =
      StreamController<BleError>.broadcast();

  final List<ScanResult> _scanResults = [];

  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;
  Stream<BluetoothConnectionState> get connectionState =>
      _connectionStateController.stream;
  Stream<List<int>> get commandResponses => _commandResponseController.stream;
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;
  Stream<BleError> get errors => _errorController.stream;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  
  // Current streaming configuration
  int _currentAcquisitionMode = 0;
  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  // Muse v3 Service UUID (from protocol specification)
  static const String museServiceUuid = 'c8c0a708-e361-4b5e-a365-98fa6b0a836f';
  static const String commandCharacteristicUuid =
      'd5913036-2d8a-41ee-85b9-4e361aa5c8a7';
  
  // Data Characteristic UUID - в документации ДВА варианта!
  static const String dataCharacteristicUuid1 =
      '04d05b73-e46e-4dad-86c4-467ee8209e3c'; // FIGURE 1 (line 569)
  static const String dataCharacteristicUuid2 =
      '09bf2c52-d1d9-c0b7-4145-475964544307'; // Section 4.2 (line 774)

  /// Start scanning for BLE devices
  Future<void> startScan() async {
    _scanResults.clear();
    _scanResultsController.add(_scanResults);

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

      FlutterBluePlus.scanResults.listen((results) {
        _scanResults.clear();
        _scanResults.addAll(results);
        _scanResultsController.add(_scanResults);
      });
    } catch (e) {
      Logger.error('Error starting scan', e);
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Connect to a specific device (SIMPLE VERSION)
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      // Listen to connection state changes
      device.connectionState.listen((state) {
        _connectionStateController.add(state);
        if (state == BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          _commandCharacteristic = null;
          _dataCharacteristic = null;
        }
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _commandCharacteristic = null;
      _dataCharacteristic = null;
    }
  }

  /// Discover services and setup notifications (SIMPLE VERSION)
  Future<bool> discoverServices() async {
    if (_connectedDevice == null) return false;

    try {
      List<BluetoothService> services =
          await _connectedDevice!.discoverServices();

      // Find Muse v3 custom service
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() ==
            museServiceUuid.toLowerCase()) {
          Logger.success('Found Muse v3 Service!');

          // Find command and data characteristics
          for (var characteristic in service.characteristics) {
            final charUuid = characteristic.uuid.toString().toLowerCase();

            if (charUuid == commandCharacteristicUuid.toLowerCase()) {
              _commandCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);

              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  _commandResponseController.add(value);
                }
              });
            } 
            // Проверяем ОБА UUID для Data Characteristic
            else if (charUuid == dataCharacteristicUuid1.toLowerCase() ||
                     charUuid == dataCharacteristicUuid2.toLowerCase()) {
              _dataCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              
              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty && _isStreaming) {
                  _handleSensorData(value);
                }
              });
            }
          }

          return _commandCharacteristic != null;
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Send command and wait for response (SIMPLE VERSION)
  Future<List<int>?> _sendCommand(List<int> command,
      {Duration timeout = const Duration(seconds: 3)}) async {
    if (_commandCharacteristic == null) {
      return null;
    }

    try {
      // Create completer to wait for response
      final completer = Completer<List<int>>();
      StreamSubscription? subscription;

      // Listen for response
      subscription = _commandResponseController.stream.listen((response) {
        if (!completer.isCompleted) {
          completer.complete(response);
        }
      });

      // Send command
      await _commandCharacteristic!.write(command, withoutResponse: false);

      // Wait for response with timeout
      final response = await completer.future.timeout(
        timeout,
        onTimeout: () => [],
      );

      await subscription.cancel();
      return response.isNotEmpty ? response : null;
    } catch (e) {
      return null;
    }
  }

  /// Read battery level
  /// Command: CMD_BATTERY_CHARGE (0x87)
  /// Response format: [0x00, 0x03, 0x87, error_code, battery_%]
  Future<int?> readBatteryLevel() async {
    final response = await _sendCommand([0x87, 0x00]);

    if (response != null &&
        response.length >= 5 &&
        response[0] == 0x00 && // ACK
        response[2] == 0x87 && // Command code
        response[3] == 0x00) {
      // Error code OK
      return response[4]; // Battery percentage
    }

    return null;
  }

  /// Read firmware version
  /// Command: CMD_FW_VERSION (0x8a)
  /// Response: [0x00, 0x12, 0x8a, error_code, bootloader_version..., app_version..., BT_version]
  Future<Map<String, String>?> readFirmwareVersion() async {
    final response = await _sendCommand([0x8a, 0x00]);

    if (response != null &&
        response.length >= 4 &&
        response[0] == 0x00 && // ACK
        response[2] == 0x8a && // Command code
        response[3] == 0x00) {
      // Error code OK
      try {
        // Bootloader version (ASCII string with \0 terminator)
        int bootloaderEnd = 4;
        while (bootloaderEnd < response.length && response[bootloaderEnd] != 0) {
          bootloaderEnd++;
        }
        final bootloaderVersion = String.fromCharCodes(
            response.sublist(4, bootloaderEnd));

        // Application version (7 bytes after bootloader)
        int appStart = bootloaderEnd + 1;
        if (appStart + 7 <= response.length) {
          final appMajor = response[appStart];
          final appMinor = response[appStart + 1];
          final appPatch = response[appStart + 2];
          final appVersion = '$appMajor.$appMinor.$appPatch';

          // BT version (if available)
          String btVersion = '';
          if (appStart + 7 + 2 <= response.length) {
            final btMajor = response[appStart + 7];
            final btMinor = response[appStart + 8];
            btVersion = '$btMajor.$btMinor';
          }

          return {
            'bootloader': bootloaderVersion,
            'application': appVersion,
            'bluetooth': btVersion,
          };
        }
      } catch (e) {
        Logger.error('Error parsing firmware version', e);
      }
    }

    return null;
  }

  /// Read system state
  /// Command: CMD_STATE (0x82 for read)
  /// Response: [0x00, 0x03, 0x82, error_code, state_code]
  Future<String?> readSystemState() async {
    final response = await _sendCommand([0x82, 0x00]);

    if (response != null &&
        response.length >= 5 &&
        response[0] == 0x00 && // ACK
        response[2] == 0x82 && // Command code
        response[3] == 0x00) {
      // Error code OK
      return _getStateName(response[4]);
    }

    return null;
  }

  /// Get state name from state code
  String _getStateName(int stateCode) {
    switch (stateCode) {
      case 0x02:
        return 'IDLE';
      case 0x03:
        return 'STANDBY';
      case 0x04:
        return 'LOG';
      case 0x05:
        return 'READOUT';
      case 0x06:
        return 'TX (BUFFERED)';
      case 0x07:
        return 'CALIBRATION';
      case 0x08:
        return 'TX (DIRECT)';
      default:
        return 'UNKNOWN (0x${stateCode.toRadixString(16)})';
    }
  }

  /// Helper: Convert bytes to hex string for debugging
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// Handle incoming sensor data
  void _handleSensorData(List<int> data) {
    try {
      final sensorData = SensorDataParser.parsePacket(data, _currentAcquisitionMode);
      _sensorDataController.add(sensorData);
    } catch (e) {
      // Ignore parsing errors silently
    }
  }

  /// Start streaming sensor data
  /// mode: acquisition mode (combination of AcquisitionMode constants)
  /// frequency: acquisition frequency (AcquisitionFrequency constants)
  /// buffered: true for buffered mode (0x06), false for direct mode (0x08)
  Future<bool> startStreaming({
    required int mode,
    int frequency = AcquisitionFrequency.hz25,
    bool buffered = true,
  }) async {
    print('🔍 [STREAMING] Starting...');
    print('   Command Char: ${_commandCharacteristic != null ? "✓" : "✗"}');
    print('   Data Char: ${_dataCharacteristic != null ? "✓" : "✗"}');
    
    if (_commandCharacteristic == null || _dataCharacteristic == null) {
      print('❌ [STREAMING] Failed: characteristics not found');
      return false;
    }

    // ✨ КРИТИЧНО: Устройство ДОЛЖНО быть в IDLE перед запуском!
    print('🔄 [STREAMING] Setting device to IDLE first...');
    final idleCommand = [0x02, 0x01, SystemState.idle];
    final idleResponse = await _sendCommand(idleCommand);
    
    if (idleResponse == null || idleResponse.length < 3) {
      print('⚠️  [STREAMING] Warning: Could not set IDLE state');
    } else {
      print('✓ [STREAMING] Device set to IDLE');
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final state = buffered ? SystemState.txBuffered : SystemState.txDirect;
    
    final command = [
      0x02, 0x05, state,
      mode & 0xFF,
      (mode >> 8) & 0xFF,
      (mode >> 16) & 0xFF,
      frequency,
    ];
    
    print('📤 [STREAMING] Sending command: ${_bytesToHex(command)}');
    print('   Mode: 0x${mode.toRadixString(16)}');
    print('   State: 0x${state.toRadixString(16)} (${buffered ? "BUFFERED" : "DIRECT"})');
    print('   Freq: $frequency Hz');
    
    final response = await _sendCommand(command);
    
    print('📥 [STREAMING] Response: ${response != null ? _bytesToHex(response) : "NULL"}');
    
    if (response != null && response.length >= 4) {
      print('   ACK: ${response[0] == 0x00 ? "✓" : "✗ (${response[0]})"}');
      print('   Error code: ${response[3] == 0x00 ? "✓ OK" : "✗ (0x${response[3].toRadixString(16)})"}');
      
      if (response[0] == 0x00 && response[3] == 0x00) {
        _isStreaming = true;
        _currentAcquisitionMode = mode;
        print('✅ [STREAMING] Started successfully!');
        return true;
      }
    }

    print('❌ [STREAMING] Failed to start');
    return false;
  }

  /// Stop streaming
  Future<bool> stopStreaming() async {
    if (_commandCharacteristic == null) return false;

    final command = [0x02, 0x01, SystemState.idle];
    final response = await _sendCommand(command);
    
    if (response != null && response.length >= 4) {
      _isStreaming = false;
      _currentAcquisitionMode = 0;
      return true;
    }

    return false;
  }

  /// Start comprehensive sensor streaming (ALL sensors - 60 bytes)
  Future<bool> startComprehensiveStreaming() async {
    // ✨ МАКСИМАЛЬНАЯ КОМБИНАЦИЯ - ВСЕ ДОСТУПНЫЕ СЕНСОРЫ!
    final mode = AcquisitionMode.imu |           // Gyro + Accel: 12 байт
                  AcquisitionMode.magnetometer |  // Mag: 6 байт
                  AcquisitionMode.hdrAccel |      // HDR Accel: 6 байт
                  AcquisitionMode.timestamp |     // Time: 6 байт
                  AcquisitionMode.tempHumidity |  // Temp + Hum: 6 байт
                  AcquisitionMode.tempPressure |  // Temp + Press: 6 байт
                  AcquisitionMode.range |         // Range + Light: 6 байт
                  AcquisitionMode.mad;            // Man Down: 6 байт
    // ИТОГО: 12+6+6+6+6+6+6+6 = 54 байта
    // Нужно 60 → добавим ориентацию: +6 = 60 ✓
    
    return await startStreaming(
      mode: mode | AcquisitionMode.orientation, // +6 байт = 60 байт ИТОГО
      frequency: AcquisitionFrequency.hz25,
      buffered: true,
    );
  }

  /// Start environmental sensors streaming
  Future<bool> startEnvironmentalStreaming() async {
    final mode = AcquisitionMode.tempHumidity | // 6 bytes
                  AcquisitionMode.tempPressure | // 6 bytes
                  AcquisitionMode.range | // 6 bytes (light + range)
                  AcquisitionMode.timestamp; // 6 bytes
    // Total: 24 bytes
    
    return await startStreaming(
      mode: mode,
      frequency: AcquisitionFrequency.hz25,
      buffered: true,
    );
  }

  void dispose() {
    _scanResultsController.close();
    _connectionStateController.close();
    _commandResponseController.close();
    _sensorDataController.close();
    _errorController.close();
  }
}
