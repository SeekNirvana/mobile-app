import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/health_provider.dart';

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleepDuration = ref.watch(sleepDurationProvider);
    final sleepScore = ref.watch(sleepScoreProvider);
    final deep = ref.watch(deepSleepMinutesProvider);
    final light = ref.watch(lightSleepMinutesProvider);
    final rem = ref.watch(remSleepMinutesProvider);
    final awake = ref.watch(awakeSleepMinutesProvider);
    final hrv = ref.watch(hrvProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = deep + light + rem + awake;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Sleep', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            _SleepScoreCard(score: sleepScore, duration: sleepDuration),
            const SizedBox(height: 16),
            _SleepStagesCard(deep: deep, light: light, rem: rem, awake: awake, total: total, isDark: isDark),
            const SizedBox(height: 16),
            _HRVCard(hrv: hrv, isDark: isDark),
            const SizedBox(height: 16),
            _buildTip(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text('Deep sleep improved 8% this week. Keep your room cool!', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.accent))),
        ],
      ),
    );
  }
}

class _SleepScoreCard extends StatelessWidget {
  final int score;
  final double duration;
  const _SleepScoreCard({required this.score, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF3949AB)]),
        borderRadius: BorderRadius.circular(AppConstants.radiusXXL),
        boxShadow: [BoxShadow(color: AppColors.sleep.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.bedtime_rounded, color: Colors.white70, size: 18), SizedBox(width: 6), Text('Last Night', style: TextStyle(color: Colors.white70, fontSize: 14))]),
            const SizedBox(height: 12),
            Text('${duration.toStringAsFixed(1)}h', style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 4),
            Text('11:15 PM – 6:27 AM', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
          ])),
          SizedBox(width: 90, height: 90, child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 85, height: 85, child: CircularProgressIndicator(value: score / 100, strokeWidth: 7, backgroundColor: Colors.white.withValues(alpha: 0.12), valueColor: const AlwaysStoppedAnimation(Colors.white), strokeCap: StrokeCap.round)),
            Column(mainAxisSize: MainAxisSize.min, children: [Text('$score', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)), const Text('score', style: TextStyle(color: Colors.white54, fontSize: 10))]),
          ])),
        ],
      ),
    );
  }
}

class _SleepStagesCard extends StatelessWidget {
  final int deep, light, rem, awake, total;
  final bool isDark;
  const _SleepStagesCard({required this.deep, required this.light, required this.rem, required this.awake, required this.total, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusXL), border: Border.all(color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sleep Stages', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(height: 24, child: Row(children: [
          Expanded(flex: deep, child: Container(color: AppColors.sleepDeep)),
          Expanded(flex: light, child: Container(color: AppColors.sleepLight)),
          Expanded(flex: rem, child: Container(color: AppColors.sleepREM)),
          Expanded(flex: awake, child: Container(color: AppColors.sleepAwake)),
        ]))),
        const SizedBox(height: 16),
        _legend('Deep', deep, AppColors.sleepDeep, context),
        const SizedBox(height: 8),
        _legend('Light', light, AppColors.sleepLight, context),
        const SizedBox(height: 8),
        _legend('REM', rem, AppColors.sleepREM, context),
        const SizedBox(height: 8),
        _legend('Awake', awake, AppColors.sleepAwake, context),
      ]),
    );
  }

  Widget _legend(String label, int mins, Color color, BuildContext ctx) {
    final h = mins ~/ 60; final m = mins % 60;
    final pct = total > 0 ? (mins / total * 100).round() : 0;
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: Theme.of(ctx).textTheme.bodyMedium)),
      Text(h > 0 ? '${h}h ${m}m' : '${m}m', style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      SizedBox(width: 40, child: Text('$pct%', textAlign: TextAlign.end, style: Theme.of(ctx).textTheme.bodySmall)),
    ]);
  }
}

class _HRVCard extends StatelessWidget {
  final int hrv;
  final bool isDark;
  const _HRVCard({required this.hrv, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusXL), border: Border.all(color: AppColors.hrv.withValues(alpha: 0.2))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.hrv.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.timeline_rounded, color: AppColors.hrv, size: 28)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Heart Rate Variability', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('$hrv', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: AppColors.hrv, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Text('ms RMSSD', style: TextStyle(color: AppColors.hrv.withValues(alpha: 0.7), fontSize: 12)),
          ]),
          Text(hrv >= 50 ? 'Good recovery' : hrv >= 30 ? 'Normal range' : 'Below average', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.success)),
        ])),
      ]),
    );
  }
}
