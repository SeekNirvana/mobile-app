import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../plugins/ring_sdk/ring_plugin.dart';
import '../providers/ring_provider.dart';
import '../providers/health_provider.dart';

/// Global service that listens to RingPlugin.rawHealthData and dispatches
/// events to the correct Riverpod providers. Runs as long as the app is alive.
class RingDataService {
  final Ref ref;
  StreamSubscription? _healthSub;

  RingDataService(this.ref) {
    _init();
  }

  void _init() {
    _healthSub = RingPlugin.rawHealthData.listen((data) {
      final type = data['type'] as String?;
      if (type == null) return;

      switch (type) {
        case 'battery':
          final level = data['level'] as int?;
          if (level != null) {
            ref.read(batteryLevelProvider.notifier).state = level;
            debugPrint('[RingDataService] Battery: $level%');
          }
          break;

        case 'version':
          final version = data['version'] as String?;
          if (version != null) {
            ref.read(firmwareVersionProvider.notifier).state = version;
            debugPrint('[RingDataService] Version: $version');
          }
          break;

        case 'steps':
          final steps = data['steps'] as int?;
          if (steps != null) {
            ref.read(stepsProvider.notifier).state = steps;
          }
          break;

        case 'heartRate':
          debugPrint('[RingDataService] HeartRate data: $data');
          ref.read(heartRateProvider.notifier).state = {
            'heartRate': data['heartRate'] ?? 0,
            'hrv': data['hrv'] ?? 0,
            'stress': data['stress'] ?? 0,
            'temperature': data['temperature'] ?? 0,
          };
          break;

        case 'heartRateComplete':
          debugPrint('[RingDataService] Heart Rate Measurement Complete');
          ref.read(heartRateMeasuringProvider.notifier).state = false;
          break;

        case 'heartRateError':
          debugPrint('[RingDataService] Heart Rate Error: ${data['code']}');
          ref.read(heartRateMeasuringProvider.notifier).state = false;
          break;

        case 'spo2':
          debugPrint('[RingDataService] SpO2 data: $data');
          ref.read(spo2Provider.notifier).state = {
            'heartRate': data['heartRate'] ?? 0,
            'spo2': data['spo2'] ?? 0,
            'temperature': data['temperature'] ?? 0,
          };
          break;

        case 'spo2Complete':
          debugPrint('[RingDataService] SpO2 Measurement Complete');
          ref.read(spo2MeasuringProvider.notifier).state = false;
          break;

        case 'spo2Error':
          debugPrint('[RingDataService] SpO2 Error: ${data['code']}');
          ref.read(spo2MeasuringProvider.notifier).state = false;
          break;

        case 'ecg':
          // ECG not supported by ring hardware — silently ignore
          break;

        case 'bloodPressure':
          final systolic = data['systolic'] as int?;
          final diastolic = data['diastolic'] as int?;
          if (systolic != null && diastolic != null) {
            ref.read(systolicProvider.notifier).state = systolic;
            ref.read(diastolicProvider.notifier).state = diastolic;
            ref.read(bpMeasuringProvider.notifier).state = false;
            debugPrint('[RingDataService] Blood Pressure: $systolic/$diastolic');
          }
          break;

        case 'bpProgress':
          final progress = data['progress'] as int?;
          if (progress != null) {
            ref.read(bpMeasuringProvider.notifier).state = true;
            ref.read(bpProgressValueProvider.notifier).state = progress;
            debugPrint('[RingDataService] BP Progress: $progress%');
          }
          break;

        case 'bpWaveform':
          // PPG waveform during BP measurement — parse and add to provider
          final waveStr = data['data'] as String?;
          if (waveStr != null && waveStr.isNotEmpty) {
            try {
              final values = waveStr.split(',')
                  .where((s) => s.isNotEmpty)
                  .map((s) => double.tryParse(s) ?? 0.0)
                  .toList();
              final current = ref.read(ppgWaveformProvider);
              // Keep last 200 points for smooth scrolling display
              final updated = [...current, ...values];
              ref.read(ppgWaveformProvider.notifier).state =
                  updated.length > 200 ? updated.sublist(updated.length - 200) : updated;
            } catch (e) {
              debugPrint('[RingDataService] Error parsing PPG waveform: $e');
            }
          }
          break;

        case 'bpError':
          debugPrint('[RingDataService] BP Error: ${data['code']}');
          ref.read(bpMeasuringProvider.notifier).state = false;
          ref.read(bpProgressValueProvider.notifier).state = 0;
          break;

        case 'bloodPressureRaw':
        case 'bpResult':
          debugPrint('[RingDataService] BP result data: $data');
          ref.read(bpMeasuringProvider.notifier).state = false;
          break;

        case 'temperature':
          final temp = data['temperature'] as int?;
          if (temp != null && temp > 0) {
            // SDK returns temp * 10 (e.g., 365 = 36.5°C)
            ref.read(temperatureProvider.notifier).state = temp / 10.0;
            ref.read(temperatureMeasuringProvider.notifier).state = false;
            debugPrint('[RingDataService] Temperature: ${temp / 10.0}°C');
          }
          break;

        case 'temperatureTesting':
          final temp = data['temperature'] as int?;
          if (temp != null && temp > 0) {
            ref.read(temperatureProvider.notifier).state = temp / 10.0;
            // Keep measuring state true during testing
            debugPrint('[RingDataService] Temperature (testing): ${temp / 10.0}°C');
          }
          break;

        case 'temperatureError':
          debugPrint('[RingDataService] Temperature Error: ${data['code']}');
          ref.read(temperatureMeasuringProvider.notifier).state = false;
          break;

        case 'historyData':
          final current = ref.read(historyDataProvider);
          ref.read(historyDataProvider.notifier).state = [...current, data];
          // Process sleep data
          final sleepType = data['sleepType'] as int?;
          if (sleepType != null && sleepType > 0) {
            // Ring reports 5-min intervals; sleepType: 1=light, 2=deep, 3=awake, 4=REM
            switch (sleepType) {
              case 1: // Light sleep
                ref.read(lightSleepMinutesProvider.notifier).state += 5;
                break;
              case 2: // Deep sleep
                ref.read(deepSleepMinutesProvider.notifier).state += 5;
                break;
              case 3: // Awake
                ref.read(awakeSleepMinutesProvider.notifier).state += 5;
                break;
              case 4: // REM
                ref.read(remSleepMinutesProvider.notifier).state += 5;
                break;
            }
            // Update total sleep duration (hrs, not counting awake)
            final deep = ref.read(deepSleepMinutesProvider);
            final light = ref.read(lightSleepMinutesProvider);
            final rem = ref.read(remSleepMinutesProvider);
            ref.read(sleepDurationProvider.notifier).state = (deep + light + rem) / 60.0;
          }
          debugPrint('[RingDataService] History: sleep=$sleepType, HR=${data['heartRate']}');
          break;

        case 'historyComplete':
          debugPrint('[RingDataService] History sync complete, records: ${ref.read(historyDataProvider).length}');
          break;

        case 'historyError':
          debugPrint('[RingDataService] History error: ${data['code']}');
          break;

        case 'syncTime':
          debugPrint('[RingDataService] Time synced: ${data['status']}');
          break;

        case 'heartRateProgress':
        case 'spo2Progress':
        case 'heartWaveform':
        case 'spo2Waveform':
        case 'rri':
          // Silently handle known types
          break;

        default:
          debugPrint('[RingDataService] Unhandled event type: $type');
      }
    });
  }

  void dispose() {
    _healthSub?.cancel();
  }
}

final ringDataServiceProvider = Provider<RingDataService>((ref) {
  return RingDataService(ref);
});
