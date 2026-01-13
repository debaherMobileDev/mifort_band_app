import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/ble_error_handler.dart';
import '../services/logger.dart';
import '../models/sensor_data.dart';
import 'logs_screen.dart';

class StreamingScreen extends StatefulWidget {
  const StreamingScreen({super.key});

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  final BleService _bleService = BleService();
  
  // Latest sensor data
  SensorData? _latestData;
  StreamSubscription? _dataSubscription;
  
  bool _isStreaming = false;
  int _packetsReceived = 0;
  DateTime? _streamStartTime;
  
  // Device info (also displayed in list)
  int? _batteryLevel;
  String? _systemState;
  Map<String, String>? _firmwareVersion;

  @override
  void initState() {
    super.initState();
    _setupDataListener();
    _setupErrorListener();
    _autoStartStreaming(); // Автоматический запуск
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    if (_isStreaming) {
      _bleService.stopStreaming();
    }
    super.dispose();
  }
  
  void _setupErrorListener() {
    _bleService.errors.listen((error) {
      if (mounted) {
        BleErrorHandler.showErrorSnackBar(context, error);
      }
    });
  }
  
  /// Автоматический запуск streaming при открытии экрана
  Future<void> _autoStartStreaming() async {
    // ✅ ВЫЗЫВАЕМ discoverServices() т.к. пользователь приходит СРАЗУ из ScanScreen!
    // (DeviceScreen пропускается в текущем флоу)
    final servicesFound = await _bleService.discoverServices();
    if (!servicesFound) {
      Logger.error('Failed to discover services in StreamingScreen');
      return;
    }
    
    // Даём время на инициализацию
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Читаем базовые данные
    await _readDeviceInfo();
    
    // Запускаем streaming
    if (mounted) {
      await _startStreaming();
    }
    
    // Периодическое обновление базовых данных
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _readDeviceInfo();
    });
  }
  
  /// Читаем базовые данные устройства
  Future<void> _readDeviceInfo() async {
    // Battery
    final battery = await _bleService.readBatteryLevel();
    if (battery != null && mounted) {
      setState(() => _batteryLevel = battery);
    }
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    // System State
    final state = await _bleService.readSystemState();
    if (state != null && mounted) {
      setState(() => _systemState = state);
    }
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Firmware (читаем только если еще не прочитали)
    if (_firmwareVersion == null) {
      final firmware = await _bleService.readFirmwareVersion();
      if (firmware != null && mounted) {
        setState(() => _firmwareVersion = firmware);
      }
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      // ✨ КРИТИЧНО: Читаем Hardware Skills чтобы знать какие датчики есть!
      Logger.info('═══ CHECKING DEVICE CAPABILITIES ═══');
      final skills = await _bleService.readHardwareSkills();
      if (skills != null) {
        Logger.success('Hardware skills retrieved successfully');
      }
    }
  }
  
  /// Запуск streaming
  Future<void> _startStreaming() async {
    // ✨ ПРОБУЕМ ПОЛНЫЙ РЕЖИМ (60 bytes) - ВСЕ ДАТЧИКИ!
    Logger.info('═══ ATTEMPTING FULL MODE (60 bytes) ═══');
    var success = await _bleService.startComprehensiveStreaming(); // TEMP/PRESS версия
    
    if (!success) {
      Logger.warning('FULL mode (with Pressure) failed, trying ALT mode (with Humidity)...');
      success = await _bleService.startComprehensiveWithHumidity(); // TEMP/HUM версия
    }
    
    if (!success) {
      Logger.warning('60-byte modes failed, trying MEDIUM (30 bytes)...');
      success = await _bleService.startMediumStreaming(); // IMU+MAG+TIME+TEMP/HUM = 30 bytes
    }
    
    if (!success) {
      Logger.warning('Medium mode failed, trying BASIC (24 bytes)...');
      success = await _bleService.startBasicStreaming(); // IMU+MAG+TIME = 24 bytes
    }
    
    if (!success) {
      Logger.warning('Basic mode failed, trying MINIMAL (18 bytes)...');
      success = await _bleService.startMinimalStreaming(); // IMU+TIME = 18 bytes
    }
    
    if (!success) {
      Logger.error('❌ ALL MODES FAILED!');
      return;
    }
    
    Logger.success('🎉 STREAMING STARTED SUCCESSFULLY!');

    if (success && mounted) {
      setState(() {
        _isStreaming = true;
        _packetsReceived = 0;
        _streamStartTime = DateTime.now();
      });
    }
  }

  void _setupDataListener() {
    Logger.info('Setting up data listener for streaming screen...');
    _dataSubscription = _bleService.sensorDataStream.listen((data) {
      Logger.info('🎯 UI: Received sensor data in StreamingScreen');
      Logger.debug('  Has Gyro: ${data.gyroscope != null}');
      Logger.debug('  Has Accel: ${data.accelerometer != null}');
      Logger.debug('  Has Mag: ${data.magnetometer != null}');
      Logger.debug('  Has Time: ${data.timestamp != null}');
      
      if (mounted) {
        setState(() {
          _latestData = data;
          _packetsReceived++;
          Logger.success('✓ UI Updated! Total packets: $_packetsReceived');
        });
      } else {
        Logger.warning('⚠️ UI not mounted, skipping update');
      }
    });
  }

  // Метод toggle убран - теперь всегда автоматически работает

  Future<void> _disconnect() async {
    await _bleService.stopStreaming();
    await _bleService.disconnect();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beta app Muse V3'),
        actions: [
          if (_isStreaming)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LogsScreen(),
                ),
              );
            },
            tooltip: 'View Logs',
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Streaming status
            _buildStatusCard(),
            
            const SizedBox(height: 20),
            
            // ═══ ПРОСТОЙ СПИСОК ВСЕХ ДАННЫХ ═══
            
            // БАЗОВЫЕ ДАННЫЕ УСТРОЙСТВА
            const Text(
              '📱 DEVICE INFO',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            
            _buildSimpleDataRow(
              'Battery Level',
              _batteryLevel?.toDouble(),
              '%',
              Icons.battery_charging_full,
              _getBatteryColor(),
            ),
            
            _buildSimpleTextRow(
              'System State',
              _systemState ?? 'unavailable',
              Icons.settings_system_daydream,
              Colors.blue,
            ),
            
            if (_firmwareVersion != null) ...[
              _buildSimpleTextRow(
                'Firmware (App)',
                _firmwareVersion!['application'] ?? 'unavailable',
                Icons.info_outline,
                Colors.orange,
              ),
              _buildSimpleTextRow(
                'Firmware (Bootloader)',
                _firmwareVersion!['bootloader'] ?? 'unavailable',
                Icons.info_outline,
                Colors.deepOrange,
              ),
            ] else ...[
              _buildSimpleTextRow(
                'Firmware',
                'unavailable',
                Icons.info_outline,
                Colors.grey,
              ),
            ],
            
            const SizedBox(height: 16),
            const Divider(height: 2, thickness: 2),
            const SizedBox(height: 16),
            
            // ДАННЫЕ СЕНСОРОВ
            const Text(
              '📊 MOTION SENSORS',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            
            // Accelerometer
            _buildSimpleDataRow(
              'Accelerometer X',
              _latestData?.accelerometer?.x,
              'mg',
              Icons.arrow_forward,
              Colors.red,
            ),
            _buildSimpleDataRow(
              'Accelerometer Y',
              _latestData?.accelerometer?.y,
              'mg',
              Icons.arrow_upward,
              Colors.green,
            ),
            _buildSimpleDataRow(
              'Accelerometer Z',
              _latestData?.accelerometer?.z,
              'mg',
              Icons.vertical_align_center,
              Colors.blue,
            ),
            
            const Divider(height: 24),
            
            // Gyroscope
            _buildSimpleDataRow(
              'Gyroscope X',
              _latestData?.gyroscope?.x,
              'dps',
              Icons.rotate_right,
              Colors.purple,
            ),
            _buildSimpleDataRow(
              'Gyroscope Y',
              _latestData?.gyroscope?.y,
              'dps',
              Icons.rotate_right,
              Colors.deepPurple,
            ),
            _buildSimpleDataRow(
              'Gyroscope Z',
              _latestData?.gyroscope?.z,
              'dps',
              Icons.rotate_right,
              Colors.indigo,
            ),
            
            const Divider(height: 24),
            
            // Magnetometer
            _buildSimpleDataRow(
              'Magnetometer X',
              _latestData?.magnetometer?.x,
              'mG',
              Icons.compass_calibration,
              Colors.orange,
            ),
            _buildSimpleDataRow(
              'Magnetometer Y',
              _latestData?.magnetometer?.y,
              'mG',
              Icons.compass_calibration,
              Colors.deepOrange,
            ),
            _buildSimpleDataRow(
              'Magnetometer Z',
              _latestData?.magnetometer?.z,
              'mG',
              Icons.compass_calibration,
              Colors.brown,
            ),
            
            const Divider(height: 24),
            
            // Environmental
            _buildSimpleDataRow(
              'Temperature',
              _latestData?.temperature,
              '°C',
              Icons.thermostat,
              Colors.red,
            ),
            _buildSimpleDataRow(
              'Humidity',
              _latestData?.humidity,
              '%',
              Icons.water_drop,
              Colors.cyan,
            ),
            _buildSimpleDataRow(
              'Pressure',
              _latestData?.pressure,
              'hPa',
              Icons.compress,
              Colors.teal,
            ),
            
            const Divider(height: 24),
            
            // Light & Range
            _buildSimpleDataRow(
              'Light Intensity',
              _latestData?.lightIntensity,
              'lux',
              Icons.light_mode,
              Colors.yellow,
            ),
            _buildSimpleDataRow(
              'Range/Distance',
              _latestData?.range,
              'mm',
              Icons.straighten,
              Colors.green,
            ),
            
            const Divider(height: 24),
            
            // HDR Accel
            _buildSimpleDataRow(
              'HDR Accel X',
              _latestData?.hdrAccelerometer?.x,
              'mg',
              Icons.speed,
              Colors.pink,
            ),
            _buildSimpleDataRow(
              'HDR Accel Y',
              _latestData?.hdrAccelerometer?.y,
              'mg',
              Icons.speed,
              Colors.pinkAccent,
            ),
            _buildSimpleDataRow(
              'HDR Accel Z',
              _latestData?.hdrAccelerometer?.z,
              'mg',
              Icons.speed,
              Colors.red,
            ),
            
            const Divider(height: 24),
            
            // ❌ AQI sensors (CO2, VOC, PM, CO) - НЕ ПОДДЕРЖИВАЮТСЯ этим устройством
            // Удалены из UI т.к. устройство не имеет AQI expansion board
            
            const Divider(height: 24),
            
            // Orientation
            if (_latestData?.orientation != null) ...[
              _buildSimpleDataRow(
                'Quaternion W',
                _latestData!.orientation!.w,
                '',
                Icons.explore,
                Colors.deepPurple,
              ),
              _buildSimpleDataRow(
                'Quaternion I',
                _latestData!.orientation!.i,
                '',
                Icons.explore,
                Colors.deepPurple,
              ),
              _buildSimpleDataRow(
                'Quaternion J',
                _latestData!.orientation!.j,
                '',
                Icons.explore,
                Colors.deepPurple,
              ),
              _buildSimpleDataRow(
                'Quaternion K',
                _latestData!.orientation!.k,
                '',
                Icons.explore,
                Colors.deepPurple,
              ),
            ] else ...[
              _buildSimpleDataRow('Quaternion', null, '', Icons.explore, Colors.grey),
            ],
            
            const Divider(height: 24),
            
            // Man Down Detection
            _buildSimpleDataRow(
              'Man Down Detection',
              _latestData?.madLevel != null 
                ? _latestData!.madLevel!.value.toDouble()
                : null,
              _latestData?.madArmed == true ? '(Armed)' : '(Disarmed)',
              Icons.personal_injury,
              Colors.red,
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 3,
      color: _isStreaming ? Colors.green.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isStreaming ? Icons.sensors : Icons.sensors_off,
              size: 40,
              color: _isStreaming ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isStreaming ? '🟢 Auto-Streaming Active (25 Hz)' : '⚪ Connecting...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Packets: $_packetsReceived',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (_streamStartTime != null)
                    Text(
                      'Duration: ${DateTime.now().difference(_streamStartTime!).inSeconds}s',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Простой виджет для отображения одного параметра
  Widget _buildSimpleDataRow(
    String label,
    double? value,
    String unit,
    IconData icon,
    Color color,
  ) {
    final displayValue = value != null 
        ? '${value.toStringAsFixed(2)} $unit'
        : 'unavailable';
    
    final isAvailable = value != null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isAvailable ? Colors.white : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAvailable ? color.withAlpha(76) : Colors.grey.shade300, // 76 = 0.3 * 255
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: isAvailable ? color : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isAvailable ? Colors.black87 : Colors.grey,
              ),
            ),
          ),
          Text(
            displayValue,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: isAvailable ? Colors.black : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// Виджет для текстовых данных (не числовых)
  Widget _buildSimpleTextRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isAvailable = value != 'unavailable';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isAvailable ? Colors.white : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAvailable ? color.withAlpha(76) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: isAvailable ? color : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isAvailable ? Colors.black87 : Colors.grey,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: isAvailable ? Colors.black : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// Цвет батареи в зависимости от уровня
  Color _getBatteryColor() {
    if (_batteryLevel == null) return Colors.grey;
    if (_batteryLevel! > 60) return Colors.green;
    if (_batteryLevel! > 30) return Colors.orange;
    return Colors.red;
  }

  // Неиспользуемые методы удалены - используем простой список
}

