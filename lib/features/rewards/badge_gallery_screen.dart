import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

// ignore: deprecated_member_use
// Share.share is deprecated but SharePlus.share requires different setup
// Using the simpler API for now
import '../../core/constants/achievements.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/gamification_provider.dart';

class BadgeGalleryScreen extends ConsumerStatefulWidget {
  const BadgeGalleryScreen({super.key});

  @override
  ConsumerState<BadgeGalleryScreen> createState() => _BadgeGalleryScreenState();
}

class _BadgeGalleryScreenState extends ConsumerState<BadgeGalleryScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unlockedIds = ref.watch(unlockedAchievementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievement Badges'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Collection',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Unlock these unique cNFTs on Solana by building consistent health habits.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final achievement = AchievementCatalog.all[index];
                  final isUnlocked = unlockedIds.contains(achievement.id);
                  return _buildBadgeCard(context, achievement, isUnlocked, isDark);
                },
                childCount: AchievementCatalog.all.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(
    BuildContext context,
    Achievement achievement,
    bool isUnlocked,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: isUnlocked ? () => _showBadgeDetails(context, achievement) : null,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isUnlocked
                ? achievement.rarityColor.withValues(alpha: 0.5)
                : (isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight),
            width: isUnlocked ? 2 : 1,
          ),
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: achievement.rarityColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: -5,
                    offset: const Offset(0, 8),
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isUnlocked
                    ? achievement.rarityColor.withValues(alpha: 0.1)
                    : (isDark ? Colors.grey[800] : Colors.grey[100]),
              ),
              child: Text(
                achievement.emoji,
                style: TextStyle(
                  fontSize: 48,
                  color: isUnlocked ? null : Colors.grey.withValues(alpha: 0.3),
                ),
              ),
            ),
            const Spacer(),
            Text(
              achievement.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isUnlocked
                        ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
                        : Colors.grey,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isUnlocked
                    ? achievement.rarityColor.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isUnlocked
                    ? null
                    : Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: Text(
                isUnlocked ? achievement.rarityLabel : 'Locked',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isUnlocked ? achievement.rarityColor : Colors.grey,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBadgeDetails(BuildContext context, Achievement achievement) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: achievement.rarityColor.withValues(alpha: 0.1),
                  boxShadow: [
                    BoxShadow(
                      color: achievement.rarityColor.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Text(
                  achievement.emoji,
                  style: const TextStyle(fontSize: 72),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                achievement.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: achievement.rarityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  achievement.rarityLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: achievement.rarityColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                achievement.description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _shareAchievement(achievement),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _shareAchievement(Achievement achievement) {
    // Using SharePlus.instance.share for the updated API
    SharePlus.instance.share(
      ShareParams(
        text: 'I just unlocked the "${achievement.title}" achievement ${achievement.emoji} on SeekNirvana! \n\nJoin me on my wellness journey and earn NFT badges on Solana. 🧘‍♀️✨',
        subject: 'SeekNirvana Achievement Unlocked!',
      ),
    );
  }
}
