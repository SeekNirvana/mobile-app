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
          
          // Process sleep data to find the most recent night's sleep
          _processLastNightSleep(allRecords);
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

  /// Process sleep records to find the main sleep session
  /// Uses gap detection to separate naps from main sleep
  void _processLastNightSleep(List<Map<String, dynamic>> allRecords) {
    final now = DateTime.now();
    
    // Parse all records with timestamps
    final allTimedRecords = allRecords
        .where((r) {
          final time = r['time'] as int?;
          return time != null && time > 0;
        })
        .map((r) {
          final timeInSeconds = r['time'] as int;
          final timeInMillis = timeInSeconds * 1000;
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timeInMillis);
          return {
            'data': r,
            'timestamp': timeInMillis,
            'dateTime': dateTime,
            'sleepType': (r['sleepType'] as int?) ?? 0,
          };
        })
        .toList();

    // Filter for sleep records from last 48 hours (to catch late sleepers)
    final sleepRecords = allTimedRecords
        .where((r) {
          final sleepType = r['sleepType'] as int;
          final dateTime = r['dateTime'] as DateTime;
          return sleepType > 0 && dateTime.isAfter(now.subtract(const Duration(hours: 48)));
        })
        .toList();

    if (sleepRecords.isEmpty) {
      debugPrint('[RingDataService] No sleep records found');
      return;
    }

    // Sort by time (oldest first)
    sleepRecords.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

    // Find sleep sessions using gap detection (>90 min gap = new session)
    const gapThresholdMinutes = 90;
    
    List<List<Map<String, dynamic>>> sessions = [];
    List<Map<String, dynamic>> currentSession = [];
    
    for (int i = 0; i < sleepRecords.length; i++) {
      final record = sleepRecords[i];
      
      if (currentSession.isEmpty) {
        currentSession.add(record);
      } else {
        final lastRecord = currentSession.last;
        final lastTime = lastRecord['timestamp'] as int;
        final currentTime = record['timestamp'] as int;
        final gapMinutes = (currentTime - lastTime) / (1000 * 60);
        
        if (gapMinutes > gapThresholdMinutes) {
          // Gap too large, start new session
          sessions.add(currentSession);
          currentSession = [record];
        } else {
          currentSession.add(record);
        }
      }
    }
    
    // Don't forget the last session
    if (currentSession.isNotEmpty) {
      sessions.add(currentSession);
    }

    // Filter sessions by minimum duration and find the best one
    // Prefer: 1) Most recent within last 24h, 2) Longest session
    List<Map<String, dynamic>>? bestSession;
    int bestScore = 0;
    
    for (final session in sessions) {
      if (session.length < 12) continue; // At least 1 hour (12 * 5min intervals)
      
      final duration = session.length * 5; // minutes
      final endTime = session.last['dateTime'] as DateTime;
      final hoursAgo = now.difference(endTime).inHours;
      
      // Score: prefer recent sessions but also consider duration
      // Recent (< 24h) gets bonus, then longer is better
      int score = duration;
      if (hoursAgo < 24) score += 500; // Bonus for being within last 24h
      
      if (bestSession == null || score > bestScore) {
        bestSession = session;
        bestScore = score;
      }
    }

    if (bestSession == null) {
      debugPrint('[RingDataService] No valid sleep session found (min 1 hour)');
      return;
    }

    // Calculate sleep metrics for the best session only
    int lightMinutes = 0;
    int deepMinutes = 0;
    int remMinutes = 0;
    int awakeMinutes = 0;

    for (final record in bestSession) {
      final sleepType = record['sleepType'] as int;
      switch (sleepType) {
        case 1: // Light sleep
          lightMinutes += 5;
          break;
        case 2: // Deep sleep
          deepMinutes += 5;
          break;
        case 3: // Awake
          awakeMinutes += 5;
          break;
        case 4: // REM
          remMinutes += 5;
          break;
      }
    }

    // Get time range
    final sleepStart = bestSession.first['dateTime'] as DateTime;
    final sleepEnd = bestSession.last['dateTime'] as DateTime;
    final totalMinutes = lightMinutes + deepMinutes + remMinutes;

    // Update providers
    ref.read(lightSleepMinutesProvider.notifier).state = lightMinutes;
    ref.read(deepSleepMinutesProvider.notifier).state = deepMinutes;
    ref.read(remSleepMinutesProvider.notifier).state = remMinutes;
    ref.read(awakeSleepMinutesProvider.notifier).state = awakeMinutes;
    ref.read(sleepDurationProvider.notifier).state = totalMinutes / 60.0;
    ref.read(sleepStartTimeProvider.notifier).state = sleepStart;
    ref.read(sleepEndTimeProvider.notifier).state = sleepEnd;

    // Update history to show only this session
    ref.read(historyDataProvider.notifier).state = bestSession.map((r) => r['data'] as Map<String, dynamic>).toList();

    debugPrint('[RingDataService] Sleep session: ${sleepStart.toLocal()} to ${sleepEnd.toLocal()}');
    debugPrint('[RingDataService] Duration: ${totalMinutes}min (Deep:$deepMinutes Light:$lightMinutes REM:$remMinutes Awake:$awakeMinutes)');
  }

  void dispose() {
    _healthSub?.cancel();
  }
}

final ringDataServiceProvider = Provider<RingDataService>((ref) {
  return RingDataService(ref);
});
