/// Model for storing device data with metadata
class DeviceDataPoint<T> {
  final T? value;
  final DateTime? lastUpdate;
  final bool isLoading;

  const DeviceDataPoint({
    this.value,
    this.lastUpdate,
    this.isLoading = false,
  });

  /// Check if data is available
  bool get hasValue => value != null;

  /// Check if data is stale (older than 30 seconds)
  bool get isStale {
    if (lastUpdate == null) return true;
    return DateTime.now().difference(lastUpdate!).inSeconds > 30;
  }

  /// Update with new value
  DeviceDataPoint<T> copyWith({
    T? value,
    DateTime? lastUpdate,
    bool? isLoading,
  }) {
    return DeviceDataPoint<T>(
      value: value ?? this.value,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Mark as loading
  DeviceDataPoint<T> setLoading(bool loading) {
    return DeviceDataPoint<T>(
      value: value,
      lastUpdate: lastUpdate,
      isLoading: loading,
    );
  }

  /// Update value only if new value is not null
  DeviceDataPoint<T> updateIfNotNull(T? newValue) {
    if (newValue == null) {
      return setLoading(false); // Keep old value, stop loading
    }
    return DeviceDataPoint<T>(
      value: newValue,
      lastUpdate: DateTime.now(),
      isLoading: false,
    );
  }

  @override
  String toString() {
    return 'DeviceDataPoint(value: $value, lastUpdate: $lastUpdate, isLoading: $isLoading)';
  }
}

