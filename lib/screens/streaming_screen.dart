import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/ble_error_handler.dart';
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
    // Discover services
    final servicesFound = await _bleService.discoverServices();
    if (!servicesFound) return;
    
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
    }
  }
  
  /// Запуск streaming
  Future<void> _startStreaming() async {
    final success = await _bleService.startComprehensiveStreaming();

    if (success && mounted) {
      setState(() {
        _isStreaming = true;
        _packetsReceived = 0;
        _streamStartTime = DateTime.now();
      });
    }
  }

  void _setupDataListener() {
    _dataSubscription = _bleService.sensorDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _latestData = data;
          _packetsReceived++;
        });
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
        title: const Text('Muse v3 Dashboard'),
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
            
            // Air Quality
            _buildSimpleDataRow(
              'CO₂',
              _latestData?.co2?.toDouble(),
              'ppm',
              Icons.co2,
              Colors.brown,
            ),
            _buildSimpleDataRow(
              'VOC',
              _latestData?.vocPpb?.toDouble(),
              'ppb',
              Icons.air,
              Colors.lime,
            ),
            _buildSimpleDataRow(
              'PM1.0',
              _latestData?.pm1?.toDouble(),
              'μg/m³',
              Icons.grain,
              Colors.grey,
            ),
            _buildSimpleDataRow(
              'PM2.5',
              _latestData?.pm25?.toDouble(),
              'μg/m³',
              Icons.grain,
              Colors.amber,
            ),
            _buildSimpleDataRow(
              'PM10',
              _latestData?.pm10?.toDouble(),
              'μg/m³',
              Icons.grain,
              Colors.orange,
            ),
            _buildSimpleDataRow(
              'CO (Carbon Monoxide)',
              _latestData?.co,
              'ppm',
              Icons.warning,
              Colors.red,
            ),
            
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

