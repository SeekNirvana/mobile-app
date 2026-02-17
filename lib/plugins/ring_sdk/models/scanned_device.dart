class ScannedDevice {
  final String name;
  final String macAddress;
  final int rssi;
  final int? battery;
  final bool isBonded;

  const ScannedDevice({
    required this.name,
    required this.macAddress,
    required this.rssi,
    this.battery,
    this.isBonded = false,
  });

  factory ScannedDevice.fromMap(Map<String, dynamic> map) {
    return ScannedDevice(
      name: map['name'] as String? ?? 'Unknown',
      macAddress: map['macAddress'] as String? ?? '',
      rssi: map['rssi'] as int? ?? -100,
      battery: map['battery'] as int?,
      isBonded: map['isBonded'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'mac': macAddress,
    'rssi': rssi,
    'battery': battery,
    'isBonded': isBonded,
  };

  /// Signal strength as 0-4 bars
  int get signalBars {
    if (rssi >= -50) return 4;
    if (rssi >= -65) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }
}
