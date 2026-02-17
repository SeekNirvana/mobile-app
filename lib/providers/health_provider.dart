import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mock health data providers for UI development.
/// In production, these will be streamed from RingPlugin.healthData.

final heartRateProvider = StateProvider<Map<String, dynamic>>((ref) {
  return {'heartRate': 0, 'hrv': 0, 'stress': 0, 'temperature': 0};
});

final spo2Provider = StateProvider<Map<String, dynamic>>((ref) {
  return {'heartRate': 0, 'spo2': 0, 'temperature': 0};
});

final temperatureProvider = StateProvider<double>((ref) => 36.5);
final stepsProvider = StateProvider<int>((ref) => 0);
final stepGoalProvider = StateProvider<int>((ref) => 10000);
final caloriesProvider = StateProvider<int>((ref) => 385);

// Blood pressure
final systolicProvider = StateProvider<int>((ref) => 120);
final diastolicProvider = StateProvider<int>((ref) => 80);

// HRV
final hrvProvider = Provider<int>((ref) {
  final hrData = ref.watch(heartRateProvider);
  return hrData['hrv'] as int? ?? 0;
});

// Sleep
final sleepDurationProvider = StateProvider<double>((ref) => 7.2); // hours
final sleepScoreProvider = StateProvider<int>((ref) => 82);
final deepSleepMinutesProvider = StateProvider<int>((ref) => 95);
final lightSleepMinutesProvider = StateProvider<int>((ref) => 180);
final remSleepMinutesProvider = StateProvider<int>((ref) => 85);
final awakeSleepMinutesProvider = StateProvider<int>((ref) => 12);

// Health score
final healthScoreProvider = Provider<int>((ref) {
  final hrData = ref.watch(heartRateProvider);
  final hr = hrData['heartRate'] as int? ?? 0;
  final spo2Data = ref.watch(spo2Provider);
  final spo2 = spo2Data['spo2'] as int? ?? 0;
  final steps = ref.watch(stepsProvider);
  final goal = ref.watch(stepGoalProvider);
  final sleepScore = ref.watch(sleepScoreProvider);

  // Composite scoring
  int hrScore = (hr >= 60 && hr <= 100) ? 25 : 15;
  int spo2Score = spo2 >= 95 ? 25 : (spo2 >= 90 ? 20 : 10);
  int activityScore = ((steps / goal) * 25).clamp(0, 25).round();
  int sleepPart = (sleepScore * 0.25).round();

  return (hrScore + spo2Score + activityScore + sleepPart).clamp(0, 100);
});

// History data for charts (mock)
final heartRateHistoryProvider = Provider<List<double>>((ref) {
  return [68, 72, 75, 70, 69, 74, 78, 76, 72, 71, 73, 72];
});

final stepsHistoryProvider = Provider<List<double>>((ref) {
  return [5200, 8100, 6500, 9200, 7800, 10200, 6842];
});
