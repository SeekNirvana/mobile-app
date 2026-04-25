import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/achievements.dart';

class TotalXPNotifier extends Notifier<int> {
  @override
  int build() => 1250;
  void update(int value) => state = value;
}
final totalXPProvider = NotifierProvider<TotalXPNotifier, int>(TotalXPNotifier.new);

class CurrentStreakNotifier extends Notifier<int> {
  @override
  int build() => 3;
  void update(int value) => state = value;
}
final currentStreakProvider = NotifierProvider<CurrentStreakNotifier, int>(CurrentStreakNotifier.new);

final currentLevelProvider = Provider<NirvanaLevel>((ref) {
  final xp = ref.watch(totalXPProvider);
  return GamificationEngine.getLevelForXP(xp);
});

final levelProgressProvider = Provider<double>((ref) {
  final xp = ref.watch(totalXPProvider);
  return GamificationEngine.getProgressToNextLevel(xp);
});

final streakMultiplierLabelProvider = Provider<String>((ref) {
  final streak = ref.watch(currentStreakProvider);
  if (streak >= 30) return '3x';
  if (streak >= 14) return '2.5x';
  if (streak >= 7) return '2x';
  if (streak >= 3) return '1.5x';
  return '1x';
});

class UnlockedAchievementsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ['first_steps'];
  void add(String id) {
    if (!state.contains(id)) {
      state = [...state, id];
    }
  }
}
final unlockedAchievementsProvider = NotifierProvider<UnlockedAchievementsNotifier, List<String>>(UnlockedAchievementsNotifier.new);
