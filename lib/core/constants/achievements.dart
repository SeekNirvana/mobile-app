import 'package:flutter/material.dart';

class NirvanaLevel {
  final int level;
  final String title;
  final int requiredXP;
  final Color color;
  final String emoji;

  const NirvanaLevel(this.level, this.title, this.requiredXP, this.color, this.emoji);
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final String rarityLabel;
  final Color rarityColor;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.rarityLabel,
    required this.rarityColor,
  });
}

class AchievementCatalog {
  static const List<Achievement> all = [
    Achievement(
      id: 'first_steps',
      title: 'First Steps',
      description: 'Hit your step goal for the first time.',
      emoji: '👟',
      rarityLabel: 'Common',
      rarityColor: Colors.blue,
    ),
    Achievement(
      id: 'sleep_master',
      title: 'Sleep Master',
      description: 'Achieve a sleep score of 90 or above.',
      emoji: '😴',
      rarityLabel: 'Rare',
      rarityColor: Colors.purple,
    ),
    Achievement(
      id: 'streak_7',
      title: 'One Week Strong',
      description: 'Maintain a 7-day streak.',
      emoji: '🔥',
      rarityLabel: 'Epic',
      rarityColor: Colors.orange,
    ),
    Achievement(
      id: 'nirvana_seeker',
      title: 'Nirvana Seeker',
      description: 'Reach Level 10 in your journey.',
      emoji: '🧘',
      rarityLabel: 'Legendary',
      rarityColor: Colors.amber,
    ),
  ];
}

class GamificationEngine {
  static const List<NirvanaLevel> levels = [
    NirvanaLevel(1, 'Novice', 0, Colors.grey, '🌱'),
    NirvanaLevel(2, 'Seeker', 500, Colors.green, '🌿'),
    NirvanaLevel(3, 'Wanderer', 1500, Colors.teal, '🍃'),
    NirvanaLevel(4, 'Guide', 3000, Colors.blue, '🌊'),
    NirvanaLevel(5, 'Master', 5000, Colors.purple, '🔮'),
  ];

  static NirvanaLevel getLevelForXP(int xp) {
    for (int i = levels.length - 1; i >= 0; i--) {
      if (xp >= levels[i].requiredXP) {
        return levels[i];
      }
    }
    return levels.first;
  }

  static double getProgressToNextLevel(int xp) {
    final current = getLevelForXP(xp);
    final nextIndex = levels.indexOf(current) + 1;
    if (nextIndex >= levels.length) return 1.0;
    
    final next = levels[nextIndex];
    final progress = (xp - current.requiredXP) / (next.requiredXP - current.requiredXP);
    return progress.clamp(0.0, 1.0);
  }
}
