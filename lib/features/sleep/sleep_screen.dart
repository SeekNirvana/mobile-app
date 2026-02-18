import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/health_provider.dart';
import '../../providers/ring_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';
import '../../services/rem_audio_service.dart';

class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key});

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize REM audio service
    // Using addPostFrameCallback to avoid calling read during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(remAudioServiceProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final audioSettings = ref.watch(remAudioSettingsProvider);
    final remAudio = ref.read(remAudioServiceProvider);
    final deepSleep = ref.watch(deepSleepMinutesProvider);
    final lightSleep = ref.watch(lightSleepMinutesProvider);
    final remSleep = ref.watch(remSleepMinutesProvider);
    final awakeSleep = ref.watch(awakeSleepMinutesProvider);
    final sleepDuration = ref.watch(sleepDurationProvider);
    final historyData = ref.watch(historyDataProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalMinutes = deepSleep + lightSleep + remSleep + awakeSleep;
    final hasData = totalMinutes > 0;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text(
                      'Sleep & Dreams',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Sleep duration overview
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _SleepOverviewCard(
                  duration: sleepDuration,
                  deepMinutes: deepSleep,
                  lightMinutes: lightSleep,
                  remMinutes: remSleep,
                  awakeMinutes: awakeSleep,
                  isDark: isDark,
                ),
              ),
            ),

            // Sleep stages chart
            if (hasData)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _SleepStagesCard(
                    deepMinutes: deepSleep,
                    lightMinutes: lightSleep,
                    remMinutes: remSleep,
                    awakeMinutes: awakeSleep,
                    isDark: isDark,
                  ),
                ),
              ),

            // Sleep timeline from history
            if (hasData)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _SleepTimelineCard(
                    historyData: historyData,
                    isDark: isDark,
                  ),
                ),
              ),

            // Sync button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: OutlinedButton.icon(
                  onPressed: () => RingPlugin.readHistory(),
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sync Data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.sleep,
                    side: BorderSide(color: AppColors.sleep.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                    ),
                  ),
                ),
              ),
            ),

            // ── Lucid Dreaming Section ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: Text(
                  'Lucid Dreaming',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _LucidDreamingCard(
                  enabled: audioSettings.enabled,
                  onToggle: (val) => remAudio.setEnabled(val),
                  isDark: isDark,
                ),
              ),
            ),

            if (audioSettings.enabled) ...[
              // Sound Selection
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _SoundSelectionCard(
                    selectedSound: audioSettings.selectedSound,
                    sounds: audioSettings.availableSounds,
                    volume: audioSettings.volume,
                    onSoundChanged: (s) => remAudio.setSound(s),
                    onVolumeChanged: (v) => remAudio.setVolume(v),
                    onTestPlay: () => remAudio.testPlay(),
                    isPlaying: audioSettings.isPlaying,
                    isDark: isDark,
                  ),
                ),
              ),

              // How it works
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _HowItWorksCard(isDark: isDark),
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

// ─── Sleep Overview Card ───────────────────────────

class _SleepOverviewCard extends StatelessWidget {
  final double duration;
  final int deepMinutes, lightMinutes, remMinutes, awakeMinutes;
  final bool isDark;

  const _SleepOverviewCard({
    required this.duration,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = duration > 0;
    final hours = duration.floor();
    final mins = ((duration - hours) * 60).round();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.sleep.withValues(alpha: 0.15),
            AppColors.sleepDeep.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(color: AppColors.sleep.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.sleep.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.bedtime_rounded,
                  color: AppColors.sleep,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last Night',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        hasData ? '${hours}h ${mins}m' : '-- h -- m',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.sleep,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (hasData) ...[
            const SizedBox(height: 20),
            // Sleep stage breakdown
            Row(
              children: [
                _SleepStageChip('Deep', deepMinutes, AppColors.sleepDeep),
                const SizedBox(width: 8),
                _SleepStageChip('Light', lightMinutes, AppColors.sleepLight),
                const SizedBox(width: 8),
                _SleepStageChip('REM', remMinutes, AppColors.sleepREM),
                const SizedBox(width: 8),
                _SleepStageChip('Awake', awakeMinutes, AppColors.sleepAwake),
              ],
            ),
          ],
          if (!hasData) ...[
            const SizedBox(height: 12),
            Text(
              'No sleep data yet. Wear the ring overnight and sync in the morning.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SleepStageChip extends StatelessWidget {
  final String label;
  final int minutes;
  final Color color;

  const _SleepStageChip(this.label, this.minutes, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '${minutes}m',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sleep Stages Pie Chart ──────────────────────

class _SleepStagesCard extends StatelessWidget {
  final int deepMinutes, lightMinutes, remMinutes, awakeMinutes;
  final bool isDark;

  const _SleepStagesCard({
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final total = deepMinutes + lightMinutes + remMinutes + awakeMinutes;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(color: AppColors.sleep.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sleep Stages',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(
                    value: deepMinutes.toDouble(),
                    color: AppColors.sleepDeep,
                    title: '${(deepMinutes / total * 100).round()}%',
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    radius: 45,
                  ),
                  PieChartSectionData(
                    value: lightMinutes.toDouble(),
                    color: AppColors.sleepLight,
                    title: '${(lightMinutes / total * 100).round()}%',
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    radius: 45,
                  ),
                  PieChartSectionData(
                    value: remMinutes.toDouble(),
                    color: AppColors.sleepREM,
                    title: '${(remMinutes / total * 100).round()}%',
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    radius: 45,
                  ),
                  PieChartSectionData(
                    value: awakeMinutes.toDouble(),
                    color: AppColors.sleepAwake,
                    title: '${(awakeMinutes / total * 100).round()}%',
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    radius: 45,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _LegendItem('Deep', AppColors.sleepDeep),
              _LegendItem('Light', AppColors.sleepLight),
              _LegendItem('REM', AppColors.sleepREM),
              _LegendItem('Awake', AppColors.sleepAwake),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}

// ─── Sleep Timeline ──────────────────────────────

class _SleepTimelineCard extends StatelessWidget {
  final List<Map<String, dynamic>> historyData;
  final bool isDark;

  const _SleepTimelineCard({
    required this.historyData,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Filter sleep records only
    final sleepRecords = historyData
        .where((r) {
          final st = r['sleepType'];
          return st != null && st is int && st > 0;
        })
        .toList();

    if (sleepRecords.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(color: AppColors.sleep.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sleep Timeline',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Row(
              children: sleepRecords.map((r) {
                final sleepType = r['sleepType'] as int;
                Color color;
                switch (sleepType) {
                  case 1: color = AppColors.sleepLight; break;
                  case 2: color = AppColors.sleepDeep; break;
                  case 3: color = AppColors.sleepAwake; break;
                  case 4: color = AppColors.sleepREM; break;
                  default: color = Colors.grey;
                }
                // Each record is ~5 min, height shows depth
                final heightFactor = sleepType == 2 ? 1.0
                    : sleepType == 4 ? 0.75
                    : sleepType == 1 ? 0.5
                    : 0.2;
                return Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: heightFactor,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bedtime', style: Theme.of(context).textTheme.bodySmall),
              Text('Wake up', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Lucid Dreaming Toggle ───────────────────────

class _LucidDreamingCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final bool isDark;

  const _LucidDreamingCard({
    required this.enabled,
    required this.onToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.sleepREM.withValues(alpha: 0.2),
                  AppColors.sleepDeep.withValues(alpha: 0.1),
                ],
              )
            : null,
        color: enabled ? null : (isDark ? AppColors.cardDark : Colors.white),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: enabled
              ? AppColors.sleepREM.withValues(alpha: 0.4)
              : (isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.sleepREM.withValues(alpha: enabled ? 0.25 : 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: enabled ? AppColors.sleepREM : Colors.grey,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Lucid Dream Mode',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppColors.sleepREM : null,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Audio cues play during REM'
                      : 'Audio triggers for REM sleep',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: onToggle,
            activeColor: AppColors.sleepREM,
          ),
        ],
      ),
    );
  }
}

// ─── Sound Selection ─────────────────────────────

class _SoundSelectionCard extends StatelessWidget {
  final String selectedSound;
  final List<String> sounds;
  final double volume;
  final ValueChanged<String> onSoundChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback? onTestPlay;
  final bool isPlaying;
  final bool isDark;

  const _SoundSelectionCard({
    required this.selectedSound,
    required this.sounds,
    required this.volume,
    required this.onSoundChanged,
    required this.onVolumeChanged,
    this.onTestPlay,
    this.isPlaying = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: AppColors.sleepREM.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REM Audio Cue',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Sound selector dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.sleepREM.withValues(alpha: 0.3),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedSound,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, color: AppColors.sleepREM),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
                dropdownColor: isDark ? AppColors.cardDark : Colors.white,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    onSoundChanged(newValue);
                  }
                },
                items: sounds.map<DropdownMenuItem<String>>((String sound) {
                  return DropdownMenuItem<String>(
                    value: sound,
                    child: Row(
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          size: 18,
                          color: sound == selectedSound ? AppColors.sleepREM : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Text(sound),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Volume slider
          Row(
            children: [
              Icon(
                Icons.volume_down_rounded,
                color: AppColors.sleepREM.withValues(alpha: 0.6),
                size: 20,
              ),
              Expanded(
                child: Slider(
                  value: volume,
                  onChanged: onVolumeChanged,
                  activeColor: AppColors.sleepREM,
                  inactiveColor: AppColors.sleepREM.withValues(alpha: 0.15),
                ),
              ),
              Icon(
                Icons.volume_up_rounded,
                color: AppColors.sleepREM.withValues(alpha: 0.6),
                size: 20,
              ),
            ],
          ),
          Center(
            child: Text(
              'Volume: ${(volume * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.sleepREM.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Test play button
          Center(
            child: OutlinedButton.icon(
              onPressed: isPlaying ? null : onTestPlay,
              icon: isPlaying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sleepREM),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(isPlaying ? 'Playing...' : 'Test Sound'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.sleepREM,
                side: BorderSide(color: AppColors.sleepREM.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── How It Works ────────────────────────────────

class _HowItWorksCard extends StatelessWidget {
  final bool isDark;

  const _HowItWorksCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: AppColors.sleepREM.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.sleepREM, size: 20),
              const SizedBox(width: 8),
              Text(
                'How Lucid Dreaming Works',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.sleepREM,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StepItem(
            step: '1',
            title: 'Sleep Stage Detection',
            description: 'The ring monitors your sleep stages in real-time using PPG sensors.',
            color: AppColors.sleepDeep,
          ),
          _StepItem(
            step: '2',
            title: 'REM Detection',
            description: 'When REM sleep is detected, the app prepares an audio cue.',
            color: AppColors.sleepREM,
          ),
          _StepItem(
            step: '3',
            title: 'Gentle Audio Trigger',
            description: 'A subtle sound plays, just loud enough to enter your dream without waking you.',
            color: AppColors.sleepLight,
          ),
          _StepItem(
            step: '4',
            title: 'Become Aware',
            description: 'The audio becomes a cue in your dream, triggering lucid awareness.',
            color: AppColors.sleep,
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String step;
  final String title;
  final String description;
  final Color color;

  const _StepItem({
    required this.step,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              step,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
