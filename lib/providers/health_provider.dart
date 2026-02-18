import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Health data providers.
/// All values default to 0/empty. Real data comes from RingDataService
/// which updates these providers when the ring sends data.

// Heart rate data from ring measurement
final heartRateProvider = StateProvider<Map<String, dynamic>>((ref) {
  return {'heartRate': 0, 'hrv': 0, 'stress': 0, 'temperature': 0};
});

// SpO2 data from ring measurement
final spo2Provider = StateProvider<Map<String, dynamic>>((ref) {
  return {'heartRate': 0, 'spo2': 0, 'temperature': 0};
});

// Temperature (from ring, when available)
final temperatureProvider = StateProvider<double>((ref) => 0.0);

// Steps from ring
final stepsProvider = StateProvider<int>((ref) => 0);
final stepGoalProvider = StateProvider<int>((ref) => 10000);

// Calories (derived from steps, will be computed when data available)
final caloriesProvider = StateProvider<int>((ref) => 0);

// Blood pressure (from ring measurement)
final systolicProvider = StateProvider<int>((ref) => 0);
final diastolicProvider = StateProvider<int>((ref) => 0);

// HRV (derived from heartRate provider)
final hrvProvider = Provider<int>((ref) {
  final hrData = ref.watch(heartRateProvider);
  return hrData['hrv'] as int? ?? 0;
});

// Stress (derived from heartRate provider)
final stressProvider = Provider<int>((ref) {
  final hrData = ref.watch(heartRateProvider);
  return hrData['stress'] as int? ?? 0;
});

// Blood pressure measurement in progress
final bpMeasuringProvider = StateProvider<bool>((ref) => false);

// BP measurement progress (0-100)
final bpProgressValueProvider = StateProvider<int>((ref) => 0);

// PPG waveform data for live display during BP measurement
final ppgWaveformProvider = StateProvider<List<double>>((ref) => []);

// Sleep (from ring history, when available)
final sleepDurationProvider = StateProvider<double>((ref) => 0.0);
final sleepScoreProvider = StateProvider<int>((ref) => 0);
final deepSleepMinutesProvider = StateProvider<int>((ref) => 0);
final lightSleepMinutesProvider = StateProvider<int>((ref) => 0);
final remSleepMinutesProvider = StateProvider<int>((ref) => 0);
final awakeSleepMinutesProvider = StateProvider<int>((ref) => 0);

// Health score (composite, adapts as real data comes in)
final healthScoreProvider = Provider<int>((ref) {
  final hrData = ref.watch(heartRateProvider);
  final hr = hrData['heartRate'] as int? ?? 0;
  final spo2Data = ref.watch(spo2Provider);
  final spo2 = spo2Data['spo2'] as int? ?? 0;
  final steps = ref.watch(stepsProvider);
  final goal = ref.watch(stepGoalProvider);

  // When no data, show 0
  if (hr == 0 && spo2 == 0 && steps == 0) return 0;

  int hrScore = (hr >= 60 && hr <= 100) ? 25 : (hr > 0 ? 15 : 0);
  int spo2Score = spo2 >= 95 ? 25 : (spo2 >= 90 ? 20 : (spo2 > 0 ? 10 : 0));
  int activityScore = goal > 0 ? ((steps / goal) * 25).clamp(0, 25).round() : 0;

  return (hrScore + spo2Score + activityScore).clamp(0, 100);
});

// Heart rate history (populated as measurements are taken)
final heartRateHistoryProvider = StateProvider<List<double>>((ref) => []);

