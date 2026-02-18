import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/ring_provider.dart';
import '../../providers/health_provider.dart';
import '../../shared/widgets/health_card.dart';
import '../../shared/widgets/connection_indicator.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(ringConnectionStateProvider);
    final healthScore = ref.watch(healthScoreProvider);
    final hrData = ref.watch(heartRateProvider);
    final hr = hrData['heartRate'] as int? ?? 0;
    final spo2Data = ref.watch(spo2Provider);
    final spo2 = spo2Data['spo2'] as int? ?? 0;
    final steps = ref.watch(stepsProvider);
    final stepGoal = ref.watch(stepGoalProvider);
    final temp = ref.watch(temperatureProvider);
    final hrv = ref.watch(hrvProvider);
    final stress = ref.watch(stressProvider);
    final sleepDuration = ref.watch(sleepDurationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SeekNirvana',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your wellness dashboard',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const Spacer(),
                    ConnectionIndicator(
                      state: connectionState,
                      onTap: () => context.push('/scan'),
                    ),
                  ],
                ),
              ),
            ),

            // Health Score
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _HealthScoreCard(score: healthScore, isDark: isDark),
              ),
            ),

            // Quick Metrics Grid
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                delegate: SliverChildListDelegate([
                  HealthCard(
                    title: 'Heart Rate',
                    value: hr > 0 ? '$hr' : '--',
                    unit: 'BPM',
                    subtitle: hr > 0 ? 'Resting' : 'Not measured',
                    icon: Icons.favorite_rounded,
                    color: AppColors.heartRate,
                    onTap: () => context.go('/vitals'),
                  ),
                  HealthCard(
                    title: 'SpO2',
                    value: spo2 > 0 ? '$spo2' : '--',
                    unit: '%',
                    subtitle: spo2 > 0 ? (spo2 >= 95 ? 'Normal' : 'Low') : 'Not measured',
                    icon: Icons.water_drop_rounded,
                    color: AppColors.spo2,
                    onTap: () => context.go('/vitals'),
                  ),
                  HealthCard(
                    title: 'Steps',
                    value: steps > 0 ? _formatSteps(steps) : '--',
                    subtitle: steps > 0 ? '${((steps / stepGoal) * 100).round()}% of goal' : 'Not synced',
                    icon: Icons.directions_walk_rounded,
                    color: AppColors.steps,
                  ),
                  HealthCard(
                    title: 'Temperature',
                    value: temp > 0 ? temp.toStringAsFixed(1) : '--',
                    unit: '°C',
                    subtitle: temp > 0 ? 'Normal range' : 'Not measured',
                    icon: Icons.thermostat_rounded,
                    color: AppColors.temperature,
                    onTap: () => context.go('/vitals'),
                  ),
                  HealthCard(
                    title: 'HRV',
                    value: hrv > 0 ? '$hrv' : '--',
                    unit: 'ms',
                    subtitle: hrv > 0 ? (hrv >= 50 ? 'Good' : 'Low') : 'Not measured',
                    icon: Icons.timeline_rounded,
                    color: AppColors.hrv,
                  ),
                  HealthCard(
                    title: 'Sleep',
                    value: sleepDuration > 0 ? sleepDuration.toStringAsFixed(1) : '--',
                    unit: 'hrs',
                    subtitle: sleepDuration > 0 ? 'Last night' : 'Not synced',
                    icon: Icons.bedtime_rounded,
                    color: AppColors.sleep,
                    onTap: () => context.go('/sleep'),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }
}

class _HealthScoreCard extends StatelessWidget {
  final int score;
  final bool isDark;

  const _HealthScoreCard({required this.score, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6C63FF),
            Color(0xFF4A42DB),
            Color(0xFF3A32C0),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXXL),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Health Score',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$score',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getScoreLabel(score),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getScoreLabel(int score) {
    if (score >= 90) return 'Excellent!';
    if (score >= 75) return 'Very Good';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Needs Attention';
  }
}
