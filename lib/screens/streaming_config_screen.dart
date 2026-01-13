import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../services/ble_service.dart';
import 'streaming_screen.dart';

/// Screen for configuring streaming parameters
class StreamingConfigScreen extends StatefulWidget {
  const StreamingConfigScreen({super.key});

  @override
  State<StreamingConfigScreen> createState() => _StreamingConfigScreenState();
}

class _StreamingConfigScreenState extends State<StreamingConfigScreen> {
  final BleService _bleService = BleService();
  
  // Selected sensors
  bool _selectGyro = true;
  bool _selectAccel = true;
  bool _selectMag = false;
  bool _selectHDR = false;
  bool _selectOrientation = false;
  bool _selectTimestamp = true;
  bool _selectTempHum = false;
  bool _selectTempPress = false;
  bool _selectRange = false;
  bool _selectMAD = false;
  
  // AQI sensors
  bool _selectCO2 = false;
  bool _selectVOC = false;
  bool _selectDust = false;
  
  // Frequency
  int _selectedFrequency = AcquisitionFrequency.hz25;
  
  // Mode
  bool _bufferedMode = true;

  int _calculatePacketSize() {
    int size = 0;
    if (_selectGyro) size += 6;
    if (_selectAccel) size += 6;
    if (_selectMag) size += 6;
    if (_selectHDR) size += 6;
    if (_selectOrientation) size += 6;
    if (_selectTimestamp) size += 6;
    if (_selectTempHum) size += 6;
    if (_selectTempPress) size += 6;
    if (_selectRange) size += 6;
    if (_selectMAD) size += 6;
    if (_selectCO2) size += 6;
    if (_selectVOC) size += 6;
    if (_selectDust) size += 6;
    return size;
  }

  bool _isValidPacketSize(int size) {
    return size == 6 || size == 12 || size == 24 || size == 30 || size == 60;
  }

  int _buildAcquisitionMode() {
    int mode = 0;
    if (_selectGyro) mode |= AcquisitionMode.gyroscope;
    if (_selectAccel) mode |= AcquisitionMode.accelerometer;
    if (_selectMag) mode |= AcquisitionMode.magnetometer;
    if (_selectHDR) mode |= AcquisitionMode.hdrAccel;
    if (_selectOrientation) mode |= AcquisitionMode.orientation;
    if (_selectTimestamp) mode |= AcquisitionMode.timestamp;
    if (_selectTempHum) mode |= AcquisitionMode.tempHumidity;
    if (_selectTempPress) mode |= AcquisitionMode.tempPressure;
    if (_selectRange) mode |= AcquisitionMode.range;
    if (_selectMAD) mode |= AcquisitionMode.mad;
    if (_selectCO2) mode |= AcquisitionMode.co2;
    if (_selectVOC) mode |= AcquisitionMode.voc;
    if (_selectDust) mode |= AcquisitionMode.dust;
    return mode;
  }

  Future<void> _startCustomStreaming() async {
    final mode = _buildAcquisitionMode();
    
    final success = await _bleService.startStreaming(
      mode: mode,
      frequency: _selectedFrequency,
      buffered: _bufferedMode,
    );

    if (!mounted) return;

    if (success) {
      // Navigate to streaming screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const StreamingScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to start streaming'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final packetSize = _calculatePacketSize();
    final isValid = _isValidPacketSize(packetSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Streaming'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'Streaming Configuration',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select sensors to stream in real-time.\nPacket size must be: 6, 12, 24, 30, or 60 bytes.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Motion sensors
            _buildSectionTitle('Motion Sensors', Icons.sensors),
            _buildCheckbox('Gyroscope (6 bytes)', _selectGyro, (val) {
              setState(() => _selectGyro = val!);
            }),
            _buildCheckbox('Accelerometer (6 bytes)', _selectAccel, (val) {
              setState(() => _selectAccel = val!);
            }),
            _buildCheckbox('Magnetometer (6 bytes)', _selectMag, (val) {
              setState(() => _selectMag = val!);
            }),
            _buildCheckbox('HDR Accelerometer (6 bytes)', _selectHDR, (val) {
              setState(() => _selectHDR = val!);
            }),
            _buildCheckbox('Orientation (6 bytes)', _selectOrientation, (val) {
              setState(() => _selectOrientation = val!);
            }),
            
            const SizedBox(height: 16),
            
            // Environmental sensors
            _buildSectionTitle('Environmental', Icons.wb_sunny),
            _buildCheckbox('Temperature + Humidity (6 bytes)', _selectTempHum, (val) {
              setState(() {
                _selectTempHum = val!;
                if (val) _selectTempPress = false;
              });
            }),
            _buildCheckbox('Temperature + Pressure (6 bytes)', _selectTempPress, (val) {
              setState(() {
                _selectTempPress = val!;
                if (val) _selectTempHum = false;
              });
            }),
            _buildCheckbox('Range + Light (6 bytes)', _selectRange, (val) {
              setState(() => _selectRange = val!);
            }),
            
            const SizedBox(height: 16),
            
            // System
            _buildSectionTitle('System', Icons.settings),
            _buildCheckbox('Timestamp (6 bytes)', _selectTimestamp, (val) {
              setState(() => _selectTimestamp = val!);
            }),
            _buildCheckbox('Man Down Detection (6 bytes)', _selectMAD, (val) {
              setState(() => _selectMAD = val!);
            }),
            
            const SizedBox(height: 16),
            
            // Air Quality (AQI expansion)
            _buildSectionTitle('Air Quality (if AQI expansion)', Icons.air),
            _buildCheckbox('CO₂ (6 bytes)', _selectCO2, (val) {
              setState(() => _selectCO2 = val!);
            }),
            _buildCheckbox('VOC (6 bytes)', _selectVOC, (val) {
              setState(() => _selectVOC = val!);
            }),
            _buildCheckbox('Dust PM1/2.5/10 (6 bytes)', _selectDust, (val) {
              setState(() => _selectDust = val!);
            }),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            
            // Frequency selection
            _buildSectionTitle('Acquisition Frequency', Icons.speed),
            _buildFrequencySelector(),
            
            const SizedBox(height: 20),
            
            // Mode selection
            _buildSectionTitle('Streaming Mode', Icons.swap_horiz),
            _buildModeSelector(),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            
            // Packet info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isValid ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isValid ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isValid ? Icons.check_circle : Icons.error,
                    color: isValid ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Packet Size: $packetSize bytes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isValid ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                        Text(
                          isValid
                              ? 'Valid configuration ✓'
                              : 'Invalid! Must be 6, 12, 24, 30, or 60 bytes',
                          style: TextStyle(
                            fontSize: 13,
                            color: isValid ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Start button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isValid ? _startCustomStreaming : null,
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text(
                  'Start Streaming',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(20),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, Function(bool?) onChanged) {
    return CheckboxListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildFrequencySelector() {
    return Wrap(
      spacing: 8,
      children: [
        _buildFrequencyChip('25 Hz', AcquisitionFrequency.hz25),
        _buildFrequencyChip('50 Hz', AcquisitionFrequency.hz50),
        _buildFrequencyChip('100 Hz', AcquisitionFrequency.hz100),
        _buildFrequencyChip('200 Hz', AcquisitionFrequency.hz200),
      ],
    );
  }

  Widget _buildFrequencyChip(String label, int frequency) {
    final isSelected = _selectedFrequency == frequency;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedFrequency = frequency);
      },
      selectedColor: Colors.blue.shade200,
      checkmarkColor: Colors.blue.shade900,
    );
  }

  Widget _buildModeSelector() {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _bufferedMode = true),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: _bufferedMode ? Colors.blue : Colors.grey.shade300,
                width: _bufferedMode ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: _bufferedMode ? Colors.blue.shade50 : null,
            ),
            child: Row(
              children: [
                Icon(
                  _bufferedMode ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: _bufferedMode ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buffered Mode',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Lower notification rate, data pooled',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => setState(() => _bufferedMode = false),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: !_bufferedMode ? Colors.blue : Colors.grey.shade300,
                width: !_bufferedMode ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: !_bufferedMode ? Colors.blue.shade50 : null,
            ),
            child: Row(
              children: [
                Icon(
                  !_bufferedMode ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: !_bufferedMode ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct Mode',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Real-time, one packet per notification',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

