import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/achievements.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/reown_service.dart';
import '../../providers/siwx_provider.dart';

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  bool _isReownInitializing = true;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initReownService();
    });
  }
  
  Future<void> _initReownService() async {
    final reownService = ref.read(reownServiceProvider);
    if (!reownService.isInitialized) {
      setState(() => _isReownInitializing = true);
      try {
        await reownService.init(context);
      } catch (e) {
        debugPrint('Failed to initialize ReownService: $e');
      } finally {
        if (mounted) {
          setState(() => _isReownInitializing = false);
        }
      }
    } else {
      setState(() => _isReownInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentLevel = ref.watch(currentLevelProvider);
    final totalXP = ref.watch(totalXPProvider);
    final progress = ref.watch(levelProgressProvider);
    final streak = ref.watch(currentStreakProvider);
    final streakMultiplier = ref.watch(streakMultiplierLabelProvider);
    final isAuth = ref.watch(isAuthenticatedProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.screenGradient(isDark)),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rewards',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Earn \$NIRV tokens for healthy habits, unlock achievements, and track your wellness journey.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      _buildLevelHero(
                        isDark,
                        currentLevel,
                        totalXP,
                        progress,
                        streak,
                        streakMultiplier,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: isAuth 
                    ? _buildNirvBalanceCard(isDark)
                    : _buildConnectWalletCTA(isDark),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _SectionHeader(
                    eyebrow: 'Daily challenges',
                    title: 'Complete quests to earn XP',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _QuestTile(
                      icon: Icons.directions_walk_rounded,
                      title: 'Hit 10k Steps',
                      xp: 50,
                      isCompleted: false,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _QuestTile(
                      icon: Icons.bedtime_rounded,
                      title: '80+ Sleep Score',
                      xp: 40,
                      isCompleted: false,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _QuestTile(
                      icon: Icons.self_improvement_rounded,
                      title: 'Meditate for 10 minutes',
                      xp: 30,
                      isCompleted: false,
                      isDark: isDark,
                    ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SectionHeader(
                          eyebrow: 'Your collection',
                          title: 'Achievements',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => context.push('/badges'),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text('View All'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                sliver: _buildAchievementsGrid(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelHero(
    bool isDark,
    NirvanaLevel currentLevel,
    int totalXP,
    double progress,
    int streak,
    String streakMultiplier,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            currentLevel.color.withValues(alpha: 0.25),
            currentLevel.color.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXXL),
        border: Border.all(
          color: currentLevel.color.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: currentLevel.color.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: currentLevel.color.withValues(alpha: 0.2),
                  border: Border.all(
                    color: currentLevel.color.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    currentLevel.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${currentLevel.level}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: currentLevel.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentLevel.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Text(
                          '$streak',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    streakMultiplier,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$totalXP XP earned',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}% to next level',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: currentLevel.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark 
                ? AppColors.surfaceDark 
                : AppColors.surfaceLight,
              color: currentLevel.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNirvBalanceCard(bool isDark) {
    final nirvBalance = ref.watch(nirvTokenBalanceProvider);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppColors.premiumPanelDecoration(isDark),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.stars_rounded,
              color: AppColors.gold,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r'$NIRV Balance',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nirvBalance > 0 ? nirvBalance.toStringAsFixed(2) : '0.00',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.gold,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Token claiming coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold.withValues(alpha: 0.15),
              foregroundColor: AppColors.gold,
            ),
            child: const Text('Claim'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectWalletCTA(bool isDark) {
    final walletAddress = ref.watch(walletAddressProvider);
    final isWalletConnected = walletAddress != null;
    final isAuth = ref.watch(isAuthenticatedProvider);
    final siwxState = ref.watch(siwxAuthProvider);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppColors.premiumPanelDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isWalletConnected ? 'Authenticate to Claim' : 'Connect Wallet',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Earn \$NIRV for healthy habits on Solana',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isWalletConnected && !isAuth) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: siwxState.isLoading 
                  ? null 
                  : () async {
                      // Clear any previous error before trying
                      ref.read(siwxAuthProvider.notifier).clearError();
                      await ref.read(siwxAuthProvider.notifier).authenticate();
                    },
                icon: siwxState.isLoading 
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
                label: Text(siwxState.isLoading ? 'Authenticating...' : 'Sign In'),
              ),
            ),
            if (siwxState.hasError)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Authentication Failed',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      siwxState.error?.toString() ?? 'Unknown error occurred',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade300,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => ref.read(siwxAuthProvider.notifier).clearError(),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Dismiss'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
          ] else if (!isWalletConnected) ...[
            if (_isReownInitializing)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              _buildWalletConnectButton(),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Authenticated',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWalletConnectButton() {
    final appKitModal = ref.watch(reownServiceProvider).appKitModal;
    if (appKitModal == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Wallet connection unavailable. Please restart the app.'),
        ),
      );
    }
    return AppKitModalConnectButton(appKit: appKitModal);
  }

  Widget _buildAchievementsGrid(bool isDark) {
    final unlockedIds = ref.watch(unlockedAchievementsProvider);

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final achievement = AchievementCatalog.all[index];
          final isUnlocked = unlockedIds.contains(achievement.id);

          return InkWell(
            onTap: () => context.push('/badges'),
            borderRadius: BorderRadius.circular(AppConstants.radiusXL),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: AppColors.premiumPanelDecoration(isDark).copyWith(
                border: Border.all(
                  color: isUnlocked
                    ? achievement.rarityColor.withValues(alpha: 0.5)
                    : (isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    achievement.emoji,
                    style: TextStyle(
                      fontSize: 44,
                      color: isUnlocked ? null : Colors.grey.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    achievement.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isUnlocked
                        ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
                        : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isUnlocked 
                        ? achievement.rarityColor.withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      achievement.rarityLabel,
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
        },
        childCount: AchievementCatalog.all.length,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;

  const _SectionHeader({
    required this.eyebrow,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.gold,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _QuestTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int xp;
  final bool isCompleted;
  final bool isDark;

  const _QuestTile({
    required this.icon,
    required this.title,
    required this.xp,
    required this.isCompleted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.premiumPanelDecoration(isDark),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCompleted
                ? AppColors.green.withValues(alpha: 0.15)
                : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isCompleted ? AppColors.green : AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+$xp XP',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isCompleted)
            const Icon(Icons.check_circle_rounded, color: AppColors.green)
          else
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.4), 
                  width: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
