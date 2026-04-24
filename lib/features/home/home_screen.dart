import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/health_provider.dart';
import '../../providers/ring_provider.dart';
import '../../shared/widgets/brand_seal.dart';
import '../../shared/widgets/connection_indicator.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(ringConnectionStateProvider);
    final healthScore = ref.watch(healthScoreProvider);
    final hrData = ref.watch(heartRateProvider);
    final hr = hrData['heartRate'] as int? ?? 0;
    final hrv = ref.watch(hrvProvider);
    final stress = ref.watch(stressProvider);
    final spo2Data = ref.watch(spo2Provider);
    final spo2 = spo2Data['spo2'] as int? ?? 0;
    final temp = ref.watch(temperatureProvider);
    final systolic = ref.watch(systolicProvider);
    final diastolic = ref.watch(diastolicProvider);
    final sleepDuration = ref.watch(sleepDurationProvider);
    final deepSleep = ref.watch(deepSleepMinutesProvider);
    final remSleep = ref.watch(remSleepMinutesProvider);
    final lightSleep = ref.watch(lightSleepMinutesProvider);
    final awakeSleep = ref.watch(awakeSleepMinutesProvider);
    final steps = ref.watch(stepsProvider);
    final goal = ref.watch(stepGoalProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.screenGradient(isDark)),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      _LogoSeal(isDark: isDark),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SeekNirvana',
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            Text(
                              'Private wellness, made quieter and clearer.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      ConnectionIndicator(
                        state: connectionState,
                        onTap: () => context.push('/scan'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _HomeHeroCard(
                    healthScore: healthScore,
                    steps: steps,
                    goal: goal,
                    onVitals: () => context.push('/vitals'),
                    onSleep: () => context.push('/sleep'),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _SectionHeader(
                    eyebrow: 'Live dashboard',
                    title: 'Vitals at a glance',
                    actionLabel: 'Open full vitals',
                    onAction: () => context.push('/vitals'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.14,
                  ),
                  delegate: SliverChildListDelegate([
                    _MetricCard(
                      label: 'Heart rate',
                      value: hr > 0 ? '$hr' : '--',
                      unit: 'BPM',
                      detail: hr > 0 ? 'Measured now' : 'Ready to scan',
                      accent: AppColors.heartRate,
                    ),
                    _MetricCard(
                      label: 'Blood oxygen',
                      value: spo2 > 0 ? '$spo2' : '--',
                      unit: '%',
                      detail: spo2 > 0 ? 'Latest reading' : 'Ready to scan',
                      accent: AppColors.spo2,
                    ),
                    _MetricCard(
                      label: 'HRV',
                      value: hrv > 0 ? '$hrv' : '--',
                      unit: 'ms',
                      detail: hrv > 0 ? 'Recovery signal' : 'Needs measurement',
                      accent: AppColors.hrv,
                    ),
                    _MetricCard(
                      label: 'Stress',
                      value: stress > 0 ? '$stress' : '--',
                      unit: '',
                      detail: stress > 0
                          ? 'Current estimate'
                          : 'Needs measurement',
                      accent: AppColors.gold,
                    ),
                    _MetricCard(
                      label: 'Temperature',
                      value: temp > 0 ? temp.toStringAsFixed(1) : '--',
                      unit: '°C',
                      detail: temp > 0 ? 'Body temperature' : 'Ready to scan',
                      accent: AppColors.temperature,
                    ),
                    _MetricCard(
                      label: 'Blood pressure',
                      value: systolic > 0 && diastolic > 0
                          ? '$systolic/$diastolic'
                          : '--/--',
                      unit: 'mmHg',
                      detail: systolic > 0
                          ? 'PPG-based estimate'
                          : 'Measure in vitals',
                      accent: AppColors.bloodPressure,
                    ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _SectionHeader(
                    eyebrow: 'Night intelligence',
                    title: 'Sleep without the extra tab juggling',
                    actionLabel: 'Open sleep detail',
                    onAction: () => context.push('/sleep'),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: _SleepSnapshotCard(
                    totalHours: sleepDuration,
                    lightMinutes: lightSleep,
                    deepMinutes: deepSleep,
                    remMinutes: remSleep,
                    awakeMinutes: awakeSleep,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  child: _HomeQuickActions(
                    onJournal: () => context.go('/journal'),
                    onGuides: () => context.go('/guides'),
                    onActivities: () => context.push('/activities'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoSeal extends StatelessWidget {
  final bool isDark;

  const _LogoSeal({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return BrandSeal(size: 52, isDark: isDark);
  }
}

class _HomeHeroCard extends StatelessWidget {
  final int healthScore;
  final int steps;
  final int goal;
  final VoidCallback onVitals;
  final VoidCallback onSleep;

  const _HomeHeroCard({
    required this.healthScore,
    required this.steps,
    required this.goal,
    required this.onVitals,
    required this.onSleep,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102419), Color(0xFF152A22), Color(0xFF272111)],
        ),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.12),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today’s state',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppColors.gold),
          ),
          const SizedBox(height: 8),
          Text(
            '$healthScore',
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'A single score grounded in motion, oxygen, and rhythm.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white12,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$steps / $goal steps',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onVitals,
                icon: const Icon(Icons.favorite_rounded),
                label: const Text('Vitals Lab'),
              ),
              OutlinedButton.icon(
                onPressed: onSleep,
                icon: const Icon(Icons.bedtime_rounded),
                label: const Text('Sleep Detail'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.gold),
              ),
              const SizedBox(height: 4),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String detail;
  final Color accent;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.detail,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.premiumPanelDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.12),
            ),
          ),
          const Spacer(),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: accent),
                ),
                TextSpan(
                  text: unit.isEmpty ? '' : ' $unit',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SleepSnapshotCard extends StatelessWidget {
  final double totalHours;
  final int lightMinutes;
  final int deepMinutes;
  final int remMinutes;
  final int awakeMinutes;

  const _SleepSnapshotCard({
    required this.totalHours,
    required this.lightMinutes,
    required this.deepMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalMinutes = lightMinutes + deepMinutes + remMinutes + awakeMinutes;
    final deepShare = totalMinutes == 0 ? 0.0 : deepMinutes / totalMinutes;
    final remShare = totalMinutes == 0 ? 0.0 : remMinutes / totalMinutes;
    final lightShare = totalMinutes == 0 ? 0.0 : lightMinutes / totalMinutes;
    final awakeShare = totalMinutes == 0 ? 0.0 : awakeMinutes / totalMinutes;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppColors.premiumPanelDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalHours > 0
                          ? '${totalHours.toStringAsFixed(1)} hrs'
                          : '-- hrs',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: AppColors.sleep,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalHours > 0
                          ? 'Last synced night'
                          : 'Sync sleep data from your ring',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.nightlight_round, color: AppColors.gold, size: 28),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: Row(
              children: [
                _SleepBarSegment(
                  flex: (deepShare * 1000).round(),
                  color: AppColors.sleepDeep,
                ),
                _SleepBarSegment(
                  flex: (lightShare * 1000).round(),
                  color: AppColors.sleepLight,
                ),
                _SleepBarSegment(
                  flex: (remShare * 1000).round(),
                  color: AppColors.sleepREM,
                ),
                _SleepBarSegment(
                  flex: (awakeShare * 1000).round(),
                  color: AppColors.sleepAwake,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SleepLegend(
                label: 'Deep',
                value: deepMinutes,
                color: AppColors.sleepDeep,
              ),
              _SleepLegend(
                label: 'Light',
                value: lightMinutes,
                color: AppColors.sleepLight,
              ),
              _SleepLegend(
                label: 'REM',
                value: remMinutes,
                color: AppColors.sleepREM,
              ),
              _SleepLegend(
                label: 'Awake',
                value: awakeMinutes,
                color: AppColors.sleepAwake,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SleepBarSegment extends StatelessWidget {
  final int flex;
  final Color color;

  const _SleepBarSegment({required this.flex, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex <= 0 ? 1 : flex,
      child: Container(height: 10, color: color),
    );
  }
}

class _SleepLegend extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SleepLegend({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label ${value}m', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  final VoidCallback onJournal;
  final VoidCallback onGuides;
  final VoidCallback onActivities;

  const _HomeQuickActions({
    required this.onJournal,
    required this.onGuides,
    required this.onActivities,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppColors.premiumPanelDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next actions',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Move from raw health data into reflection, guidance, and practice.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onJournal,
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Open Journal'),
              ),
              OutlinedButton.icon(
                onPressed: onGuides,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Talk to Guides'),
              ),
              OutlinedButton.icon(
                onPressed: onActivities,
                icon: const Icon(Icons.self_improvement_rounded),
                label: const Text('Mindful Activities'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
