import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../plugins/ring_sdk/ring_plugin.dart';
import '../providers/ring_provider.dart';
import '../providers/health_provider.dart';
import 'sleep_log_service.dart';

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
          ref.read(heartRateLastScanProvider.notifier).state = DateTime.now();
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
          ref.read(spo2LastScanProvider.notifier).state = DateTime.now();
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
            ref.read(bpLastScanProvider.notifier).state = DateTime.now();
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
            // Handle different SDK formats:
            // Android: temp * 10 (e.g., 365 = 36.5°C)
            // iOS: temp * 100 (e.g., 3634 = 36.34°C)
            double normalizedTemp;
            if (temp > 1000) {
              // Likely iOS format (temp * 100)
              normalizedTemp = temp / 100.0;
            } else {
              // Android format (temp * 10)
              normalizedTemp = temp / 10.0;
            }
            ref.read(temperatureProvider.notifier).state = normalizedTemp;
            ref.read(temperatureMeasuringProvider.notifier).state = false;
            ref.read(temperatureLastScanProvider.notifier).state = DateTime.now();
            debugPrint('[RingDataService] Temperature: $normalizedTemp°C (raw: $temp)');
          }
          break;

        case 'temperatureTesting':
          final temp = data['temperature'] as int?;
          if (temp != null && temp > 0) {
            double normalizedTemp;
            if (temp > 1000) {
              normalizedTemp = temp / 100.0;
            } else {
              normalizedTemp = temp / 10.0;
            }
            ref.read(temperatureProvider.notifier).state = normalizedTemp;
            // Keep measuring state true during testing
            debugPrint('[RingDataService] Temperature (testing): $normalizedTemp°C');
          }
          break;

        case 'temperatureError':
          debugPrint('[RingDataService] Temperature Error: ${data['code']}');
          ref.read(temperatureMeasuringProvider.notifier).state = false;
          break;

        case 'rssi':
          final rssiValue = data['rssi'] as int?;
          if (rssiValue != null) {
            ref.read(rssiProvider.notifier).state = rssiValue;
          }
          break;

        case 'historyStart':
          // Reset all history accumulators before new sync
          ref.read(historyDataProvider.notifier).state = [];
          ref.read(lightSleepMinutesProvider.notifier).state = 0;
          ref.read(deepSleepMinutesProvider.notifier).state = 0;
          ref.read(remSleepMinutesProvider.notifier).state = 0;
          ref.read(awakeSleepMinutesProvider.notifier).state = 0;
          ref.read(sleepDurationProvider.notifier).state = 0.0;
          ref.read(sleepStartTimeProvider.notifier).state = null;
          ref.read(sleepEndTimeProvider.notifier).state = null;
          debugPrint('[RingDataService] History sync started - reset counters');
          break;

        case 'historyData':
          // Just collect all data - we'll process it when sync is complete
          final current = ref.read(historyDataProvider);
          ref.read(historyDataProvider.notifier).state = [...current, data];
          debugPrint('[RingDataService] History: sleep=${data['sleepType']}, HR=${data['heartRate']}, time=${data['time']}');
          break;

        case 'historyComplete':
          final allRecords = ref.read(historyDataProvider);
          debugPrint('[RingDataService] History sync complete, total records: ${allRecords.length}');
          
          // Process and store sleep data by date (async, don't block)
          sleepLogService.processNewRecords(allRecords).then((_) {
            _updateSleepDisplay();
          });
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

  /// Update sleep display providers based on selected date
  /// Defaults to showing the most recent sleep session
  void _updateSleepDisplay({DateTime? forDate}) {
    sleepLogService.init();
    
    SleepSession? session;
    
    if (forDate != null) {
      // Get specific date
      session = sleepLogService.getSessionForDate(forDate);
    } else {
      // Try today first, then yesterday, then most recent
      session = sleepLogService.getTodaySession() ??
                sleepLogService.getYesterdaySession() ??
                sleepLogService.getAllSessions().firstOrNull;
    }

    if (session == null) {
      debugPrint('[RingDataService] No sleep session found for display');
      // Clear providers
      ref.read(lightSleepMinutesProvider.notifier).state = 0;
      ref.read(deepSleepMinutesProvider.notifier).state = 0;
      ref.read(remSleepMinutesProvider.notifier).state = 0;
      ref.read(awakeSleepMinutesProvider.notifier).state = 0;
      ref.read(sleepDurationProvider.notifier).state = 0.0;
      ref.read(sleepStartTimeProvider.notifier).state = null;
      ref.read(sleepEndTimeProvider.notifier).state = null;
      ref.read(historyDataProvider.notifier).state = [];
      return;
    }

    // Update providers with session data
    ref.read(lightSleepMinutesProvider.notifier).state = session.lightMinutes;
    ref.read(deepSleepMinutesProvider.notifier).state = session.deepMinutes;
    ref.read(remSleepMinutesProvider.notifier).state = session.remMinutes;
    ref.read(awakeSleepMinutesProvider.notifier).state = session.awakeMinutes;
    ref.read(sleepDurationProvider.notifier).state = session.durationHours;
    ref.read(sleepStartTimeProvider.notifier).state = session.sleepStart;
    ref.read(sleepEndTimeProvider.notifier).state = session.sleepEnd;
    ref.read(historyDataProvider.notifier).state = session.records
        .map((r) => {
          'time': r.timestamp,
          'sleepType': r.sleepType,
          'heartRate': r.heartRate,
          'bloodOxygen': r.bloodOxygen,
          'temperature': r.temperature,
          'hrv': r.hrv,
          'stress': r.stress,
        })
        .toList();

    debugPrint('[RingDataService] Displaying sleep for ${session.date.toIso8601String()}: '
        '${session.sleepStart.toLocal()} to ${session.sleepEnd.toLocal()}, '
        '${session.totalMinutes}min total');
  }

  void dispose() {
    _healthSub?.cancel();
  }
}

final ringDataServiceProvider = Provider<RingDataService>((ref) {
  return RingDataService(ref);
});
