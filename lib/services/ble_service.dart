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
    if (_connectedDevice == null) {
      Logger.error('discoverServices: No connected device');
      return false;
    }

    // ✨ ЗАЩИТА ОТ ПОВТОРНОГО ВЫЗОВА
    if (_commandCharacteristic != null && _dataCharacteristic != null) {
      Logger.info('Services already discovered, skipping...');
      return true;
    }

    try {
      Logger.info('Starting service discovery...');
      List<BluetoothService> services =
          await _connectedDevice!.discoverServices();

      Logger.info('Found ${services.length} services');

      // Find Muse v3 custom service
      for (var service in services) {
        Logger.debug('Service: ${service.uuid}');
        
        if (service.uuid.toString().toLowerCase() ==
            museServiceUuid.toLowerCase()) {
          Logger.success('Found Muse v3 service');
          
          // Показываем ВСЕ характеристики
          Logger.info('Characteristics found: ${service.characteristics.length}');
          for (var char in service.characteristics) {
            Logger.debug('  - ${char.uuid}');
          }

          // Find command and data characteristics
          for (var characteristic in service.characteristics) {
            final charUuid = characteristic.uuid.toString().toLowerCase();
            Logger.debug('Checking char: $charUuid');

            if (charUuid == commandCharacteristicUuid.toLowerCase()) {
              Logger.success('MATCHED Command Characteristic!');
              _commandCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              Logger.success('Notifications enabled for Command');

              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  Logger.debug('Command response: ${_bytesToHex(value)}');
                  _commandResponseController.add(value);
                }
              });
            } 
            // Проверяем ОБА UUID для Data Characteristic
            else if (charUuid == dataCharacteristicUuid1.toLowerCase() ||
                     charUuid == dataCharacteristicUuid2.toLowerCase()) {
              Logger.success('MATCHED Data Characteristic!');
              Logger.info('  UUID: $charUuid');
              if (charUuid == dataCharacteristicUuid1.toLowerCase()) {
                Logger.info('  Using UUID1 (FIGURE 1): $dataCharacteristicUuid1');
              } else {
                Logger.info('  Using UUID2 (Section 4.2): $dataCharacteristicUuid2');
              }
              _dataCharacteristic = characteristic;
              
              try {
                await characteristic.setNotifyValue(true);
                Logger.success('Notifications enabled for Data');
              } catch (e) {
                Logger.error('Failed to enable notifications on Data char', e);
                throw e;
              }
              
              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  if (_isStreaming) {
                    Logger.debug('Data packet received: ${value.length} bytes');
                    _handleSensorData(value);
                  } else {
                    Logger.debug('Data packet IGNORED (not streaming): ${value.length} bytes');
                  }
                }
              });
            } else {
              Logger.debug('No match for: $charUuid');
            }
          }
          
          Logger.info('═══ DISCOVERY RESULT ═══');
          Logger.info('Command Char: ${_commandCharacteristic != null ? "✓" : "✗"}');
          Logger.info('Data Char: ${_dataCharacteristic != null ? "✓" : "✗"}');

          if (_commandCharacteristic == null) {
            Logger.error('Command characteristic NOT found!');
          }
          if (_dataCharacteristic == null) {
            Logger.error('Data characteristic NOT found!');
          }

          return _commandCharacteristic != null;
        }
      }
      
      Logger.error('Muse v3 service NOT found');
      return false;
    } catch (e) {
      Logger.error('Error discovering services', e);
      return false;
    }
  }

  /// Send command and wait for response (SIMPLE VERSION)
  Future<List<int>?> _sendCommand(List<int> command,
      {Duration timeout = const Duration(seconds: 3)}) async {
    if (_commandCharacteristic == null) {
      Logger.error('_sendCommand: Command characteristic is null');
      return null;
    }

    try {
      Logger.debug('Sending command: ${_bytesToHex(command)}');
      
      // Create completer to wait for response
      final completer = Completer<List<int>>();
      StreamSubscription? subscription;

      // Listen for response
      subscription = _commandResponseController.stream.listen((response) {
        if (!completer.isCompleted) {
          Logger.debug('Received response: ${_bytesToHex(response)}');
          completer.complete(response);
        }
      });

      // Send command
      await _commandCharacteristic!.write(command, withoutResponse: false);
      Logger.debug('Command written to characteristic');

      // Wait for response with timeout
      final response = await completer.future.timeout(
        timeout,
        onTimeout: () {
          Logger.warning('Command timeout after ${timeout.inSeconds}s');
          return [];
        },
      );

      await subscription.cancel();
      
      if (response.isEmpty) {
        Logger.warning('No response received');
        return null;
      }
      
      return response;
    } catch (e) {
      Logger.error('Error sending command', e);
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

  /// Read device hardware skills (what sensors are available)
  /// Command: CMD_DEVICE_SKILLS (0x8f) with HARDWARE_SKILLS (0x00)
  /// Response: [0x00, 0x06, 0x8f, error_code, skills_4bytes]
  Future<Map<String, bool>?> readHardwareSkills() async {
    Logger.info('Reading hardware skills...');
    final response = await _sendCommand([0x8f, 0x01, 0x00]); // 0x00 = Hardware skills

    if (response != null &&
        response.length >= 8 &&
        response[0] == 0x00 && // ACK
        response[2] == 0x8f && // Command code
        response[3] == 0x00) {
      // Error code OK
      
      // Skills is a 32-bit unsigned integer (little endian)
      final skillsValue = (response[4]) |
                          (response[5] << 8) |
                          (response[6] << 16) |
                          (response[7] << 24);
      
      Logger.info('Hardware skills value: 0x${skillsValue.toRadixString(16)}');
      
      final skills = {
        'Gyroscope': (skillsValue & 0x0001) != 0,
        'Accelerometer': (skillsValue & 0x0002) != 0,
        'Magnetometer': (skillsValue & 0x0004) != 0,
        'HDR Accelerometer': (skillsValue & 0x0008) != 0,
        'Temperature': (skillsValue & 0x0010) != 0,
        'Relative Humidity': (skillsValue & 0x0020) != 0,
        'Barometric Pressure': (skillsValue & 0x0040) != 0,
        'Light (Visible)': (skillsValue & 0x0080) != 0,
        'Light (IR)': (skillsValue & 0x0100) != 0,
        'Range': (skillsValue & 0x0200) != 0,
        'Microphone': (skillsValue & 0x0400) != 0,
      };
      
      Logger.info('═══ HARDWARE SKILLS ═══');
      skills.forEach((key, value) {
        Logger.info('  $key: ${value ? "✓" : "✗"}');
      });
      
      return skills;
    }

    Logger.warning('Failed to read hardware skills');
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
      Logger.debug('══════════════════════════════════');
      Logger.debug('📦 Received sensor data BUFFER');
      Logger.debug('   Buffer Length: ${data.length} bytes');
      Logger.debug('   Mode: 0x${_currentAcquisitionMode.toRadixString(16)}');
      
      // Calculate packet size
      final packetSize = _calculatePacketSize(_currentAcquisitionMode);
      Logger.debug('   Packet Size: $packetSize bytes');
      
      // В BUFFERED MODE буфер содержит НЕСКОЛЬКО пакетов!
      // Data Characteristic = 128 bytes, но используется только 120 bytes
      final usableBufferSize = data.length > 120 ? 120 : data.length;
      final numPackets = (usableBufferSize / packetSize).floor();
      
      Logger.info('📊 BUFFERED MODE: $numPackets packets in buffer');
      
      // Парсим ВСЕ пакеты в буфере
      for (int i = 0; i < numPackets; i++) {
        final start = i * packetSize;
        final end = start + packetSize;
        
        if (end <= data.length) {
          final packet = data.sublist(start, end);
          
          // Показываем детальные логи только для ПЕРВОГО пакета
          final showDetails = (i == 0);
          if (showDetails) {
            Logger.debug('   → Parsing packet ${i + 1}/$numPackets (offset: $start)');
          }
          
          final sensorData = SensorDataParser.parsePacket(
            packet, 
            _currentAcquisitionMode,
            showDetailedLogs: showDetails,
          );
          _sensorDataController.add(sensorData);
        }
      }
      
      Logger.success('✓ All $numPackets packets parsed and sent to UI');
    } catch (e, stackTrace) {
      Logger.error('✗ PARSING ERROR!', e);
      Logger.debug('Stack trace: $stackTrace');
    }
  }

  /// Calculate packet size for given acquisition mode
  int _calculatePacketSize(int mode) {
    int size = 0;
    
    // IMU includes both gyro and accel
    if ((mode & AcquisitionMode.imu) == AcquisitionMode.imu) {
      size += 12; // GYR + AXL together
    } else {
      if ((mode & AcquisitionMode.gyroscope) != 0) size += 6;
      if ((mode & AcquisitionMode.accelerometer) != 0) size += 6;
    }
    
    if ((mode & AcquisitionMode.magnetometer) != 0) size += 6;
    if ((mode & AcquisitionMode.hdrAccel) != 0) size += 6;
    if ((mode & AcquisitionMode.orientation) != 0) size += 6;
    if ((mode & AcquisitionMode.timestamp) != 0) size += 6;
    if ((mode & AcquisitionMode.tempHumidity) != 0) size += 6;
    if ((mode & AcquisitionMode.tempPressure) != 0) size += 6;
    if ((mode & AcquisitionMode.range) != 0) size += 6;
    if ((mode & AcquisitionMode.mad) != 0) size += 6;
    if ((mode & AcquisitionMode.sound) != 0) size += 6;
    
    return size;
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
    Logger.info('═══ STARTING STREAMING ═══');
    Logger.info('Command Char: ${_commandCharacteristic != null ? "✓" : "✗"}');
    Logger.info('Data Char: ${_dataCharacteristic != null ? "✓" : "✗"}');
    
    if (_commandCharacteristic == null || _dataCharacteristic == null) {
      Logger.error('Failed: characteristics not found');
      return false;
    }
    
    // Валидация размера пакета
    final packetSize = _calculatePacketSize(mode);
    Logger.info('Calculated packet size: $packetSize bytes');
    
    if (![6, 12, 18, 24, 30, 60].contains(packetSize)) {
      Logger.error('❌ INVALID PACKET SIZE: $packetSize bytes!');
      Logger.error('   Allowed sizes: 6, 12, 18, 24, 30, 60');
      Logger.error('   Mode: 0x${mode.toRadixString(16)}');
      return false;
    } else {
      Logger.success('✓ Packet size is valid: $packetSize bytes');
    }

    // ✨ КРИТИЧНО: Устройство ДОЛЖНО быть в IDLE перед запуском!
    Logger.info('Setting device to IDLE first...');
    final idleCommand = [0x02, 0x01, SystemState.idle];
    final idleResponse = await _sendCommand(idleCommand);
    
    if (idleResponse == null || idleResponse.length < 3) {
      Logger.warning('Could not set IDLE state');
    } else {
      Logger.success('Device set to IDLE: ${_bytesToHex(idleResponse)}');
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
    
    Logger.info('Sending command: ${_bytesToHex(command)}');
    Logger.info('  Mode: 0x${mode.toRadixString(16)}');
    Logger.info('  State: 0x${state.toRadixString(16)} (${buffered ? "BUFFERED" : "DIRECT"})');
    Logger.info('  Freq: $frequency Hz');
    
    final response = await _sendCommand(command);
    
    Logger.info('Response: ${response != null ? _bytesToHex(response) : "NULL"}');
    
    if (response != null && response.length >= 4) {
      Logger.info('  ACK: ${response[0] == 0x00 ? "✓" : "✗ (${response[0]})"}');
      Logger.info('  Error code: ${response[3] == 0x00 ? "✓ OK" : "✗ (0x${response[3].toRadixString(16)})"}');
      
      if (response[0] == 0x00 && response[3] == 0x00) {
        _isStreaming = true;
        _currentAcquisitionMode = mode;
        Logger.success('Streaming started successfully!');
        return true;
      } else {
        Logger.error('Streaming start FAILED - error code: 0x${response[3].toRadixString(16)}');
      }
    } else {
      Logger.error('Invalid or no response from device');
    }

    Logger.error('Failed to start streaming');
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

  /// Start comprehensive sensor streaming (60 bytes - ВСЕ датчики)
  Future<bool> startComprehensiveStreaming() async {
    // ✨ МАКСИМАЛЬНАЯ КОМБИНАЦИЯ - ВСЕ ДОСТУПНЫЕ ДАТЧИКИ
    // Используем TEMP/PRESSURE вместо TEMP/HUMIDITY чтобы получить и температуру и давление
    Logger.info('Starting FULL mode: 60 bytes (IMU+MAG+HDR+QUAT+TIME+TEMP/PRESS+RANGE+MAD+SOUND)');
    
    final mode = AcquisitionMode.imu |           // Gyro + Accel: 12 байт
                  AcquisitionMode.magnetometer |  // Mag: 6 байт
                  AcquisitionMode.hdrAccel |      // HDR Accel: 6 байт
                  AcquisitionMode.orientation |   // Quaternion: 6 байт
                  AcquisitionMode.timestamp |     // Time: 6 байт
                  AcquisitionMode.tempPressure |  // Temp + Pressure: 6 байт (даёт Temp + Pressure, НО БЕЗ Humidity!)
                  AcquisitionMode.range |         // Range + Light: 6 байт
                  AcquisitionMode.mad |           // Man Down: 6 байт
                  AcquisitionMode.sound;          // Microphone: 6 байт
    // ИТОГО: 12+6+6+6+6+6+6+6+6 = 60 байт ✓
    
    return await startStreaming(
      mode: mode,
      frequency: AcquisitionFrequency.hz25,
      buffered: true,
    );
  }
  
  /// Start comprehensive WITH humidity (60 bytes - альтернативная версия)
  Future<bool> startComprehensiveWithHumidity() async {
    // Используем TEMP/HUMIDITY вместо TEMP/PRESSURE
    // Получаем: Temp + Humidity, НО БЕЗ Pressure!
    Logger.info('Starting ALT mode: 60 bytes (IMU+MAG+HDR+QUAT+TIME+TEMP/HUM+RANGE+MAD+SOUND)');
    
    final mode = AcquisitionMode.imu |           // 12 bytes
                  AcquisitionMode.magnetometer |  // 6 bytes
                  AcquisitionMode.hdrAccel |      // 6 bytes
                  AcquisitionMode.orientation |   // 6 bytes
                  AcquisitionMode.timestamp |     // 6 bytes
                  AcquisitionMode.tempHumidity |  // Temp + Humidity: 6 bytes
                  AcquisitionMode.range |         // 6 bytes
                  AcquisitionMode.mad |           // 6 bytes
                  AcquisitionMode.sound;          // 6 bytes
    // ИТОГО: 60 bytes ✓
    
    return await startStreaming(
      mode: mode,
      frequency: AcquisitionFrequency.hz25,
      buffered: true,
    );
  }
  
  /// Start medium sensor streaming (30 bytes)
  Future<bool> startMediumStreaming() async {
    Logger.info('Starting MEDIUM mode: 30 bytes (IMU+MAG+TIME+TEMP/HUM+RANGE)');
    
    final mode = AcquisitionMode.imu |           // 12 bytes
                  AcquisitionMode.magnetometer |  // 6 bytes
                  AcquisitionMode.timestamp |     // 6 bytes
                  AcquisitionMode.tempHumidity;   // 6 bytes
    // ИТОГО: 30 bytes ✓
    
    return await startStreaming(
      mode: mode,
      frequency: AcquisitionFrequency.hz25,
      buffered: true,
    );
  }
  
  /// Start basic sensor streaming (24 bytes)
  Future<bool> startBasicStreaming() async {
    Logger.info('Starting BASIC mode: 24 bytes (IMU+MAG+TIME)');
    
    final mode = AcquisitionMode.imu |           // 12 bytes
                  AcquisitionMode.magnetometer |  // 6 bytes
                  AcquisitionMode.timestamp;     // 6 bytes
    // ИТОГО: 24 bytes ✓
    
    return await startStreaming(
      mode: mode,
      frequency: AcquisitionFrequency.hz25,
      buffered: true,
    );
  }
  
  /// Start minimal sensor streaming (18 bytes) - для отладки
  Future<bool> startMinimalStreaming() async {
    Logger.info('Starting MINIMAL mode: 18 bytes (IMU+TIME)');
    
    final mode = AcquisitionMode.imu |           // 12 bytes
                  AcquisitionMode.timestamp;     // 6 bytes
    // ИТОГО: 18 bytes ✓
    
    return await startStreaming(
      mode: mode,
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
