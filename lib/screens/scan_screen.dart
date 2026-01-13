import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';
import 'streaming_screen.dart'; // Сразу на дашборд!

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final BleService _bleService = BleService();
  bool _isScanning = false;
  bool _isBluetoothOn = false;

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
    _requestPermissions();
  }

  Future<void> _checkBluetoothState() async {
    // Check if Bluetooth is on
    FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _isBluetoothOn = state == BluetoothAdapterState.on;
      });
    });
  }

  Future<void> _requestPermissions() async {
    // Request necessary permissions
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
    });
    await _bleService.startScan();
    // Auto-stop after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    });
  }

  Future<void> _stopScan() async {
    await _bleService.stopScan();
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    bool connected = await _bleService.connectToDevice(device);

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (connected) {
      // ✨ СРАЗУ ПЕРЕХОДИМ НА ДАШБОРД!
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const StreamingScreen(),
        ),
      );
    } else {
      // SnackBar отключен - только логирование
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan for Devices'),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isBluetoothOn)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red,
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bluetooth is turned off. Please enable it.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isBluetoothOn
                    ? (_isScanning ? _stopScan : _startScan)
                    : null,
                child: Text(_isScanning ? 'Stop Scan' : 'Start Scan'),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ScanResult>>(
              stream: _bleService.scanResults,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      'No devices found.\nTap "Start Scan" to begin.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final result = snapshot.data![index];
                    final device = result.device;
                    final rssi = result.rssi;

                    return ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(
                        device.platformName.isNotEmpty
                            ? device.platformName
                            : 'Unknown Device',
                      ),
                      subtitle: Text(device.remoteId.toString()),
                      trailing: Text('$rssi dBm'),
                      onTap: () => _connectToDevice(device),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bleService.stopScan();
    super.dispose();
  }
}

