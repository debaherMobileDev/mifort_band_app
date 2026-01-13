import 'dart:typed_data';
import 'dart:math' as math;
import '../models/sensor_data.dart';

/// Parser for Muse v3 sensor data according to protocol specification
class SensorDataParser {
  // Sensitivity coefficients (full scale dependent - these are defaults)
  static const double gyroSensitivity = 0.035; // 1000 dps
  static const double accelSensitivity = 0.244; // 8g
  static const double magSensitivity = 0.146156088; // 4 Gauss
  static const double hdrSensitivity = 49.0; // 100g

  /// Parse sensor data packet based on acquisition mode
  static SensorData parsePacket(List<int> data, int acquisitionMode) {
    final buffer = Uint8List.fromList(data);
    int offset = 0;

    Vector3D? gyro;
    Vector3D? accel;
    Vector3D? mag;
    Vector3D? hdrAccel;
    Quaternion? orientation;
    DateTime? timestamp;
    double? temperature;
    double? humidity;
    double? pressure;
    double? lightIntensity;
    double? range;
    MADLevel? madLevel;
    bool? madArmed;
    int? co2;
    int? vocPpb;
    int? vocAQI;
    int? pm1, pm25, pm10;
    double? co;

    // Parse based on acquisition mode bits
    if ((acquisitionMode & AcquisitionMode.gyroscope) != 0) {
      gyro = _parseGyroscope(buffer, offset);
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.accelerometer) != 0) {
      accel = _parseAccelerometer(buffer, offset);
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.magnetometer) != 0) {
      mag = _parseMagnetometer(buffer, offset);
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.hdrAccel) != 0) {
      hdrAccel = _parseHDRAccelerometer(buffer, offset);
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.orientation) != 0) {
      orientation = _parseQuaternion(buffer, offset);
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.timestamp) != 0) {
      timestamp = _parseTimestamp(buffer, offset);
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.tempHumidity) != 0) {
      final tempHum = _parseTempHumidity(buffer, offset);
      temperature = tempHum['temp'];
      humidity = tempHum['humidity'];
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.tempPressure) != 0) {
      final tempPress = _parseTempPressure(buffer, offset);
      temperature = tempPress['temp'];
      pressure = tempPress['pressure'];
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.range) != 0) {
      final rangeLight = _parseRangeLight(buffer, offset);
      range = rangeLight['range'];
      lightIntensity = rangeLight['light'];
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.mad) != 0) {
      final mad = _parseMAD(buffer, offset);
      madLevel = mad['level'];
      madArmed = mad['armed'];
      offset += 6;
    }

    // AQI expansion sensors
    if ((acquisitionMode & AcquisitionMode.co2) != 0) {
      co2 = _parseCO2(buffer, offset);
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.voc) != 0) {
      final voc = _parseVOC(buffer, offset);
      vocAQI = voc['aqi'];
      vocPpb = voc['ppb'];
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.dust) != 0) {
      final dust = _parseDust(buffer, offset);
      pm1 = dust['pm1'];
      pm25 = dust['pm25'];
      pm10 = dust['pm10'];
      offset += 6;
    }

    if ((acquisitionMode & AcquisitionMode.coGas) != 0) {
      co = _parseCO(buffer, offset);
      offset += 6;
    }

    return SensorData(
      gyroscope: gyro,
      accelerometer: accel,
      magnetometer: mag,
      hdrAccelerometer: hdrAccel,
      orientation: orientation,
      timestamp: timestamp,
      temperature: temperature,
      humidity: humidity,
      pressure: pressure,
      lightIntensity: lightIntensity,
      range: range,
      madLevel: madLevel,
      madArmed: madArmed,
      co2: co2,
      vocPpb: vocPpb,
      vocAQI: vocAQI,
      pm1: pm1,
      pm25: pm25,
      pm10: pm10,
      co: co,
    );
  }

  /// Parse 3D gyroscope data (6 bytes)
  static Vector3D _parseGyroscope(Uint8List buffer, int offset) {
    final x = _readInt16(buffer, offset) * gyroSensitivity;
    final y = _readInt16(buffer, offset + 2) * gyroSensitivity;
    final z = _readInt16(buffer, offset + 4) * gyroSensitivity;
    return Vector3D(x, y, z);
  }

  /// Parse 3D accelerometer data (6 bytes)
  static Vector3D _parseAccelerometer(Uint8List buffer, int offset) {
    final x = _readInt16(buffer, offset) * accelSensitivity;
    final y = _readInt16(buffer, offset + 2) * accelSensitivity;
    final z = _readInt16(buffer, offset + 4) * accelSensitivity;
    return Vector3D(x, y, z);
  }

  /// Parse 3D magnetometer data (6 bytes)
  static Vector3D _parseMagnetometer(Uint8List buffer, int offset) {
    final x = _readInt16(buffer, offset) * magSensitivity;
    final y = _readInt16(buffer, offset + 2) * magSensitivity;
    final z = _readInt16(buffer, offset + 4) * magSensitivity;
    return Vector3D(x, y, z);
  }

  /// Parse HDR accelerometer data (6 bytes, 12-bit left-justified)
  static Vector3D _parseHDRAccelerometer(Uint8List buffer, int offset) {
    final x = (_readInt16(buffer, offset) / 16) * hdrSensitivity;
    final y = (_readInt16(buffer, offset + 2) / 16) * hdrSensitivity;
    final z = (_readInt16(buffer, offset + 4) / 16) * hdrSensitivity;
    return Vector3D(x, y, z);
  }

  /// Parse orientation quaternion (6 bytes - only imaginary parts transmitted)
  static Quaternion _parseQuaternion(Uint8List buffer, int offset) {
    final i = _readInt16(buffer, offset) / 32767.0;
    final j = _readInt16(buffer, offset + 2) / 32767.0;
    final k = _readInt16(buffer, offset + 4) / 32767.0;
    
    // Calculate real part (quaternion is normalized)
    final w = math.sqrt(1 - (i * i + j * j + k * k)).abs();
    
    return Quaternion(w, i, j, k);
  }

  /// Parse timestamp (6 bytes)
  static DateTime _parseTimestamp(Uint8List buffer, int offset) {
    int timestamp = 0;
    for (int i = 0; i < 6; i++) {
      timestamp |= (buffer[offset + i] << (i * 8));
    }
    
    // Add reference epoch: 26 January 2020 00:53:20 (1580000000)
    final milliseconds = timestamp + (1580000000 * 1000);
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// Parse temperature and humidity (6 bytes)
  static Map<String, double> _parseTempHumidity(Uint8List buffer, int offset) {
    final tempRaw = _readUint16(buffer, offset);
    final humRaw = _readUint16(buffer, offset + 2);
    
    final temp = tempRaw * 0.002670 - 45;
    final hum = humRaw * 0.001907 - 6;
    
    return {'temp': temp, 'humidity': hum};
  }

  /// Parse temperature and pressure (6 bytes)
  static Map<String, double> _parseTempPressure(Uint8List buffer, int offset) {
    // Pressure is 3 bytes
    final pressRaw = buffer[offset] | 
                     (buffer[offset + 1] << 8) | 
                     (buffer[offset + 2] << 16);
    final tempRaw = _readUint16(buffer, offset + 3);
    
    final pressure = pressRaw / 4096.0;
    final temp = tempRaw / 100.0;
    
    return {'temp': temp, 'pressure': pressure};
  }

  /// Parse range and light intensity (6 bytes)
  static Map<String, double> _parseRangeLight(Uint8List buffer, int offset) {
    final range = _readUint16(buffer, offset).toDouble();
    final visLight = _readUint16(buffer, offset + 2);
    final irLight = _readUint16(buffer, offset + 4);
    
    // Calculate lux based on light source type
    double lux = 0;
    if (irLight > 0) {
      final ratio = irLight / visLight;
      
      if (ratio < 0.109) {
        lux = 1.534 * visLight - 3.759 * irLight;
      } else if (ratio < 0.429) {
        lux = 1.339 * visLight - 1.972 * irLight;
      } else if (ratio < 0.95 * 1.45) {
        lux = 0.701 * visLight - 0.483 * irLight;
      } else if (ratio < 1.5 * 1.45) {
        lux = 2.0 * 0.701 * visLight - 1.18 * 0.483 * irLight;
      } else if (ratio < 2.5 * 1.45) {
        lux = 4.0 * 0.701 * visLight - 1.33 * 0.483 * irLight;
      } else {
        lux = 8.0 * 0.701 * visLight;
      }
    }
    
    return {'range': range, 'light': lux};
  }

  /// Parse Man Down Detection (6 bytes)
  static Map<String, dynamic> _parseMAD(Uint8List buffer, int offset) {
    final alertLevel = buffer[offset];
    final armedFlag = buffer[offset + 1];
    
    return {
      'level': MADLevel.fromValue(alertLevel),
      'armed': armedFlag == 1,
    };
  }

  /// Parse CO2 (6 bytes)
  static int _parseCO2(Uint8List buffer, int offset) {
    return _readUint16(buffer, offset);
  }

  /// Parse VOC (6 bytes)
  static Map<String, int> _parseVOC(Uint8List buffer, int offset) {
    final aqi = buffer[offset];
    final ppb = _readUint16(buffer, offset + 1);
    // CO2e is at offset + 3
    
    return {'aqi': aqi, 'ppb': ppb};
  }

  /// Parse Dust/Particulate Matter (6 bytes)
  static Map<String, int> _parseDust(Uint8List buffer, int offset) {
    final pm1 = _readUint16(buffer, offset);
    final pm25 = _readUint16(buffer, offset + 2);
    final pm10 = _readUint16(buffer, offset + 4);
    
    return {'pm1': pm1, 'pm25': pm25, 'pm10': pm10};
  }

  /// Parse CO gas (6 bytes)
  static double _parseCO(Uint8List buffer, int offset) {
    final bytes = Uint8List(4);
    bytes[0] = buffer[offset];
    bytes[1] = buffer[offset + 1];
    bytes[2] = buffer[offset + 2];
    bytes[3] = buffer[offset + 3];
    
    return ByteData.sublistView(bytes).getFloat32(0, Endian.little);
  }

  /// Read signed 16-bit integer (Little Endian)
  static int _readInt16(Uint8List buffer, int offset) {
    final value = buffer[offset] | (buffer[offset + 1] << 8);
    // Convert to signed
    return value > 32767 ? value - 65536 : value;
  }

  /// Read unsigned 16-bit integer (Little Endian)
  static int _readUint16(Uint8List buffer, int offset) {
    return buffer[offset] | (buffer[offset + 1] << 8);
  }
}

