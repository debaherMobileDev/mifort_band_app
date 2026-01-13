import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../services/ble_error_handler.dart';
import 'streaming_screen.dart';
// import 'streaming_config_screen.dart'; // Commented out - simplified version

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final BleService _bleService = BleService();

  // Device data with last update timestamps
  int? _batteryLevel;
  DateTime? _batteryLastUpdate;
  
  Map<String, String>? _firmwareVersion;
  DateTime? _firmwareLastUpdate;
  
  String? _systemState;
  DateTime? _systemStateLastUpdate;
  
  bool _isLoading = false;
  String? _errorMessage;
  
  // Loading states for individual parameters
  bool _batteryLoading = false;
  bool _firmwareLoading = false;
  bool _stateLoading = false;
  
  // Auto-refresh
  bool _autoRefresh = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initializeDevice();
    _listenToConnectionState();
    _listenToErrors();
  }
  
  void _listenToErrors() {
    _bleService.errors.listen((error) {
      if (mounted) {
        BleErrorHandler.showErrorSnackBar(context, error);
      }
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeDevice() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Discover services and setup notifications
    bool servicesFound = await _bleService.discoverServices();

    if (!servicesFound) {
      setState(() {
        _errorMessage = 'Muse v3 service not found';
        _isLoading = false;
      });
      return;
    }

    // Give device a moment to be ready
    await Future.delayed(const Duration(milliseconds: 500));

    // Read all data
    await _readAllData();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _readAllData() async {
    // Read battery
    setState(() => _batteryLoading = true);
    final battery = await _bleService.readBatteryLevel();
    if (mounted) {
      setState(() {
        // ✅ СОХРАНЯЕМ ТОЛЬКО ЕСЛИ ДАННЫЕ ПРИШЛИ
        if (battery != null) {
          _batteryLevel = battery;
          _batteryLastUpdate = DateTime.now();
        }
        _batteryLoading = false;
      });
    }

    // Small delay between commands
    await Future.delayed(const Duration(milliseconds: 300));

    // Read firmware version
    setState(() => _firmwareLoading = true);
    final firmware = await _bleService.readFirmwareVersion();
    if (mounted) {
      setState(() {
        // ✅ СОХРАНЯЕМ ТОЛЬКО ЕСЛИ ДАННЫЕ ПРИШЛИ
        if (firmware != null) {
          _firmwareVersion = firmware;
          _firmwareLastUpdate = DateTime.now();
        }
        _firmwareLoading = false;
      });
    }

    // Small delay between commands
    await Future.delayed(const Duration(milliseconds: 300));

    // Read system state
    setState(() => _stateLoading = true);
    final state = await _bleService.readSystemState();
    if (mounted) {
      setState(() {
        // ✅ СОХРАНЯЕМ ТОЛЬКО ЕСЛИ ДАННЫЕ ПРИШЛИ
        if (state != null) {
          _systemState = state;
          _systemStateLastUpdate = DateTime.now();
        }
        _stateLoading = false;
      });
    }
  }

  void _listenToConnectionState() {
    _bleService.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        if (mounted) {
          Navigator.pop(context);
          // SnackBar отключен
        }
      }
    });
  }

  Future<void> _disconnect() async {
    await _bleService.disconnect();
    if (mounted) {
      Navigator.pop(context);
    }
  }
  
  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
      
      if (_autoRefresh) {
        // Start periodic refresh every 5 seconds
        _refreshTimer = Timer.periodic(
          const Duration(seconds: 5),
          (timer) => _readAllData(),
        );
      } else {
        // Stop periodic refresh
        _refreshTimer?.cancel();
        _refreshTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.platformName.isNotEmpty
            ? widget.device.platformName
            : 'Muse v3 Device'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _readAllData,
            tooltip: 'Refresh data',
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Connection status
                  const SizedBox(height: 20),
                  const Text(
                    'device has been connected',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.device.remoteId.toString(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Battery Level
                  _buildDataCard(
                    icon: Icons.battery_charging_full,
                    title: 'Battery Level',
                    value: _batteryLevel != null
                        ? '$_batteryLevel%'
                        : 'Not available',
                    color: _getBatteryColor(_batteryLevel),
                    lastUpdate: _batteryLastUpdate,
                    isLoading: _batteryLoading,
                  ),

                  const SizedBox(height: 16),

                  // System State
                  _buildDataCard(
                    icon: Icons.settings_system_daydream,
                    title: 'System State',
                    value: _systemState ?? 'Not available',
                    color: Colors.blue,
                    lastUpdate: _systemStateLastUpdate,
                    isLoading: _stateLoading,
                  ),

                  const SizedBox(height: 16),

                  // Firmware Version
                  _buildFirmwareCard(),

                  const SizedBox(height: 30),

                  // Refresh button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _readAllData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh All Data'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Auto-refresh toggle
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _toggleAutoRefresh,
                      icon: Icon(
                        _autoRefresh ? Icons.stop_circle : Icons.play_circle,
                        color: _autoRefresh ? Colors.red : Colors.green,
                      ),
                      label: Text(
                        _autoRefresh 
                          ? 'Stop Auto-Refresh (5s)' 
                          : 'Start Auto-Refresh (5s)',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        side: BorderSide(
                          color: _autoRefresh ? Colors.red : Colors.green,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),
                  
                  // Real-time sensor streaming
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade600, Colors.purple.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.shade200,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.sensors,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Real-Time Sensor Monitoring',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'View live data from all sensors:\n🎯 Gyro • Accel • Mag\n🌡️ Temp • Humidity • Pressure\n💡 Light • Range • Air Quality',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const StreamingScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.show_chart),
                            label: const Text('Open Sensor Dashboard'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.all(14),
                            ),
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

  Widget _buildDataCard({
    required IconData icon,
    required String title,
    required String value,
    Color? color,
    DateTime? lastUpdate,
    bool isLoading = false,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color ?? Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  if (lastUpdate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Updated: ${_formatTime(lastUpdate)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildFirmwareCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 40, color: Colors.orange),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Firmware Version',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                if (_firmwareLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_firmwareVersion != null) ...[
              const SizedBox(height: 16),
              _buildFirmwareRow('Bootloader', _firmwareVersion!['bootloader']),
              _buildFirmwareRow('Application', _firmwareVersion!['application']),
              if (_firmwareVersion!['bluetooth']?.isNotEmpty ?? false)
                _buildFirmwareRow('Bluetooth', _firmwareVersion!['bluetooth']),
              if (_firmwareLastUpdate != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Updated: ${_formatTime(_firmwareLastUpdate!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Not available',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirmwareRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value ?? 'N/A',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Color _getBatteryColor(int? battery) {
    if (battery == null) return Colors.grey;
    if (battery > 60) return Colors.green;
    if (battery > 30) return Colors.orange;
    return Colors.red;
  }
}
