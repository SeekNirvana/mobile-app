enum HealthDataType {
  heartRate,
  spo2,
  bloodPressure,
  bloodGlucose,
  ecg,
  temperature,
  steps,
  sleep,
  hrv,
}

class HealthDataPoint {
  final HealthDataType type;
  final double value;
  final double? value2; // For BP: systolic=value, diastolic=value2
  final DateTime timestamp;
  final Map<String, dynamic>? extra;

  const HealthDataPoint({
    required this.type,
    required this.value,
    this.value2,
    required this.timestamp,
    this.extra,
  });

  factory HealthDataPoint.fromMap(Map<String, dynamic> map) {
    return HealthDataPoint(
      type: HealthDataType.values.firstWhere(
        (e) => e.name == (map['type'] as String? ?? ''),
        orElse: () => HealthDataType.heartRate,
      ),
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      value2: (map['value2'] as num?)?.toDouble(),
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
      extra: map['extra'] != null
          ? Map<String, dynamic>.from(map['extra'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'value': value,
    'value2': value2,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'extra': extra,
  };

  String get formattedValue {
    switch (type) {
      case HealthDataType.heartRate:
        return '${value.round()} BPM';
      case HealthDataType.spo2:
        return '${value.round()}%';
      case HealthDataType.bloodPressure:
        return '${value.round()}/${value2?.round() ?? 0}';
      case HealthDataType.bloodGlucose:
        return '${value.toStringAsFixed(1)} mmol/L';
      case HealthDataType.ecg:
        return '${value.toStringAsFixed(2)} mV';
      case HealthDataType.temperature:
        return '${value.toStringAsFixed(1)}°C';
      case HealthDataType.steps:
        return '${value.round()}';
      case HealthDataType.sleep:
        return '${(value / 60).toStringAsFixed(1)}h';
      case HealthDataType.hrv:
        return '${value.round()} ms';
    }
  }
}
