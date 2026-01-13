// Models for Muse v3 sensor data streaming

/// 3D vector for sensor data (gyro, accel, mag)
class Vector3D {
  final double x;
  final double y;
  final double z;

  const Vector3D(this.x, this.y, this.z);

  @override
  String toString() => '($x, $y, $z)';
}

/// Orientation as quaternion
class Quaternion {
  final double w; // real part
  final double i; // imaginary i
  final double j; // imaginary j
  final double k; // imaginary k

  const Quaternion(this.w, this.i, this.j, this.k);

  @override
  String toString() => 'Q($w, $i, $j, $k)';
}

/// Man Down Detection levels
enum MADLevel {
  none(0),
  level1(1),
  level2(2),
  level3(3);

  final int value;
  const MADLevel(this.value);

  static MADLevel fromValue(int value) {
    return MADLevel.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MADLevel.none,
    );
  }
}

/// Complete sensor data from streaming
class SensorData {
  // Motion sensors
  final Vector3D? gyroscope; // dps (degrees per second)
  final Vector3D? accelerometer; // mg (millig)
  final Vector3D? magnetometer; // mGauss
  final Vector3D? hdrAccelerometer; // mg (high dynamic range)
  
  // Orientation
  final Quaternion? orientation;
  
  // Environmental sensors
  final double? temperature; // °C
  final double? humidity; // %
  final double? pressure; // hPa
  final double? lightIntensity; // lux
  final double? range; // mm
  
  // Air quality (AQI expansion)
  final int? co2; // ppm
  final int? vocPpb; // ppb
  final int? vocAQI; // 1-5
  final int? pm1; // μg/m³
  final int? pm25; // μg/m³
  final int? pm10; // μg/m³
  final double? co; // ppm
  
  // System
  final DateTime? timestamp;
  final MADLevel? madLevel;
  final bool? madArmed;

  const SensorData({
    this.gyroscope,
    this.accelerometer,
    this.magnetometer,
    this.hdrAccelerometer,
    this.orientation,
    this.temperature,
    this.humidity,
    this.pressure,
    this.lightIntensity,
    this.range,
    this.co2,
    this.vocPpb,
    this.vocAQI,
    this.pm1,
    this.pm25,
    this.pm10,
    this.co,
    this.timestamp,
    this.madLevel,
    this.madArmed,
  });

  @override
  String toString() {
    final parts = <String>[];
    if (gyroscope != null) parts.add('Gyro: $gyroscope');
    if (accelerometer != null) parts.add('Accel: $accelerometer');
    if (temperature != null) parts.add('Temp: ${temperature!.toStringAsFixed(1)}°C');
    if (humidity != null) parts.add('Humidity: ${humidity!.toStringAsFixed(1)}%');
    return 'SensorData(${parts.join(', ')})';
  }
}

/// Data acquisition modes (can be combined with bitwise OR)
class AcquisitionMode {
  static const int gyroscope = 0x000001;      // 6 bytes
  static const int accelerometer = 0x000002;   // 6 bytes
  static const int imu = 0x000003;             // 12 bytes (gyro + accel)
  static const int magnetometer = 0x000004;    // 6 bytes
  static const int dof9 = 0x000007;            // 18 bytes (gyro + accel + mag)
  static const int hdrAccel = 0x000008;        // 6 bytes
  static const int imuHdr = 0x000011;          // 18 bytes
  static const int orientation = 0x000010;     // 6 bytes (quaternion)
  static const int timestamp = 0x000020;       // 6 bytes
  static const int tempHumidity = 0x000040;    // 6 bytes
  static const int tempPressure = 0x000080;    // 6 bytes
  static const int range = 0x000100;           // 6 bytes
  static const int mad = 0x000200;             // 6 bytes (Man Down Detection)
  static const int sound = 0x000400;           // 6 bytes (microphone)
  
  // AQI expansion modes
  static const int co2 = 0x010000;             // 6 bytes
  static const int tempHumAqi = 0x020000;      // 6 bytes
  static const int voc = 0x040000;             // 6 bytes
  static const int dust = 0x080000;            // 6 bytes
  static const int vocIndex = 0x100000;        // 6 bytes
  static const int coGas = 0x200000;           // 6 bytes
  static const int atemp = 0x400000;           // 6 bytes
}

/// Acquisition frequencies
class AcquisitionFrequency {
  static const int hz25 = 0x01;
  static const int hz50 = 0x02;
  static const int hz100 = 0x04;
  static const int hz200 = 0x08;
  static const int hz400 = 0x10;
  static const int hz800 = 0x20;
  static const int hz1600 = 0x40;
}

/// System states
class SystemState {
  static const int idle = 0x02;
  static const int standby = 0x03;
  static const int log = 0x04;
  static const int readout = 0x05;
  static const int txBuffered = 0x06;  // Streaming - buffered mode
  static const int calibration = 0x07;
  static const int txDirect = 0x08;    // Streaming - direct mode
}

