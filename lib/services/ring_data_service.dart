import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../plugins/ring_sdk/ring_plugin.dart';
import '../providers/ring_provider.dart';
import '../providers/health_provider.dart';

/// Service to listen to RingPlugin streams and update Riverpod providers.
/// This ensures data is captured even when screens are not active.
class RingDataService {
  final Ref ref;
  StreamSubscription? _healthDataSubscription;

  RingDataService(this.ref) {
    _init();
  }

  void _init() {
    _healthDataSubscription = RingPlugin.healthData.listen((data) {
      // HealthDataPoint is a structured object, but for now we might receive maps
      // depending on how the plugin stream is typed. 
      // The plugin actually emits HealthDataPoint, let's see.
      // Wait, ring_plugin.dart has two streams: healthData (HealthDataPoint) and rawHealthData (Map).
      // Let's use rawHealthData for flexibility as we iterate.
    });

    // Actually, let's listen to rawHealthData to handle all types including battery/version/steps
    RingPlugin.rawHealthData.listen((data) {
      final type = data['type'] as String?;
      if (type == null) return;

      switch (type) {
        case 'battery':
          final level = data['level'] as int?;
          if (level != null) {
            ref.read(batteryLevelProvider.notifier).state = level;
          }
          break;
        case 'version':
          final version = data['version'] as String?;
          if (version != null) {
            ref.read(firmwareVersionProvider.notifier).state = version;
          }
          break;
        case 'steps':
          final steps = data['steps'] as int?;
          if (steps != null) {
            ref.read(stepsProvider.notifier).state = steps;
          }
          break;
        case 'heartRate':
           // data: {heartRate: int, hrv: int, stress: int, temperature: int}
           // Log for debugging
           print("Received Heart Rate Data: $data");
           ref.read(heartRateProvider.notifier).state = {
             'heartRate': data['heartRate'] ?? 0,
             'hrv': data['hrv'] ?? 0,
             'stress': data['stress'] ?? 0,
             'temperature': data['temperature'] ?? 0,
           };
           break;
        case 'heartRateComplete':
           print("Heart Rate Measurement Complete");
           ref.read(heartRateMeasuringProvider.notifier).state = false;
           break;
        case 'heartRateError':
           print("Heart Rate Measurement Error: ${data['code']}");
           ref.read(heartRateMeasuringProvider.notifier).state = false;
           break;
        case 'spo2':
           // data: {heartRate: int, spo2: int, temperature: int}
           print("Received SpO2 Data: $data");
           ref.read(spo2Provider.notifier).state = {
             'heartRate': data['heartRate'] ?? 0,
             'spo2': data['spo2'] ?? 0,
             'temperature': data['temperature'] ?? 0,
           };
           break;
        case 'spo2Complete':
           print("SpO2 Measurement Complete");
           ref.read(spo2MeasuringProvider.notifier).state = false;
           break;
        case 'spo2Error':
           print("SpO2 Measurement Error: ${data['code']}");
           ref.read(spo2MeasuringProvider.notifier).state = false;
           break;
        case 'historyProgress':
        case 'historyComplete':
           // Handle history if needed
           break;
      }
    });
  }

  void dispose() {
    _healthDataSubscription?.cancel();
  }
}

final ringDataServiceProvider = Provider<RingDataService>((ref) {
  return RingDataService(ref);
});
