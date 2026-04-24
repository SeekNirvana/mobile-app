import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/health_provider.dart';
import '../../providers/ring_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';
import '../../services/rem_audio_service.dart';
import '../../services/sleep_log_service.dart';

/// Provider for currently selected sleep date
final selectedSleepDateProvider = StateProvider<DateTime?>((ref) => null);

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
      sleepLogService.init();
    });
  }

  String _getDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) return 'Today';
    if (dateDay == yesterday) return 'Yesterday';
    if (today.difference(dateDay).inDays < 7) {
      return DateFormat('EEEE').format(date);
    }
    return DateFormat('MMM d').format(date);
  }

  void _loadSessionForDate(DateTime date) async {
    final session = sleepLogService.getSessionForDate(date);
    if (session != null) {
      await _updateDisplayFromSession(session);
    }
  }

  Future<void> _updateDisplayFromSession(SleepSession session) async {
    ref.read(sleepDurationProvider.notifier).state = session.durationHours;
    ref.read(lightSleepMinutesProvider.notifier).state = session.lightMinutes;
    ref.read(deepSleepMinutesProvider.notifier).state = session.deepMinutes;
    ref.read(remSleepMinutesProvider.notifier).state = session.remMinutes;
    ref.read(awakeSleepMinutesProvider.notifier).state = session.awakeMinutes;
    if (session.records.isNotEmpty) {
      final firstRecord = session.records.first;
      final lastRecord = session.records.last;
      ref.read(sleepStartTimeProvider.notifier).state =
          DateTime.fromMillisecondsSinceEpoch(firstRecord.timestamp * 1000);
      ref.read(sleepEndTimeProvider.notifier).state =
          DateTime.fromMillisecondsSinceEpoch(lastRecord.timestamp * 1000);
    }
  }

  void _goBackOrHome() {
    if (GoRouter.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  void _showLogViewer(BuildContext context) async {
    final logPath = await sleepLogService.exportLogFile();
    if (!context.mounted) return;
    final sessions = sleepLogService.getAllSessions();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _LogViewerSheet(sessions: sessions, logPath: logPath),
    );
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
    final sleepStart = ref.watch(sleepStartTimeProvider);
    final sleepEnd = ref.watch(sleepEndTimeProvider);
    final historyData = ref.watch(historyDataProvider);
    final selectedDate = ref.watch(selectedSleepDateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalMinutes = deepSleep + lightSleep + remSleep + awakeSleep;
    final hasData = totalMinutes > 0;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.screenGradient(isDark)),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Header with back button
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded),
                        onPressed: _goBackOrHome,
                      ),
                      Expanded(
                        child: Text(
                          'Sleep & Dreams',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      // Log file button
                      IconButton(
                        icon: const Icon(Icons.description_outlined),
                        tooltip: 'View Log',
                        onPressed: () => _showLogViewer(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Date Navigator
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _DateNavigator(
                    selectedDate: selectedDate,
                    onDateChanged: (date) {
                      ref.read(selectedSleepDateProvider.notifier).state = date;
                      _loadSessionForDate(date);
                    },
                  ),
                ),
              ),

              // Sleep duration overview
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _SleepOverviewCard(
                    duration: sleepDuration,
                    deepMinutes: deepSleep,
                    lightMinutes: lightSleep,
                    remMinutes: remSleep,
                    awakeMinutes: awakeSleep,
                    sleepStart: sleepStart,
                    sleepEnd: sleepEnd,
                    dateLabel: selectedDate != null
                        ? _getDateLabel(selectedDate)
                        : 'Last Night',
                    isDark: isDark,
                  ),
                ),
              ),

              // Sleep stages chart
              if (hasData)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _SleepTimelineCard(
                      historyData: historyData,
                      sleepStart: sleepStart,
                      sleepEnd: sleepEnd,
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
                    label: const Text('Sync Sleep Data'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.sleep,
                      side: BorderSide(
                        color: AppColors.sleep.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusLG,
                        ),
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
      ),
    );
  }
}

// ─── Sleep Overview Card ───────────────────────────

class _SleepOverviewCard extends StatelessWidget {
  final double duration;
  final int deepMinutes, lightMinutes, remMinutes, awakeMinutes;
  final DateTime? sleepStart;
  final DateTime? sleepEnd;
  final String dateLabel;
  final bool isDark;

  const _SleepOverviewCard({
    required this.duration,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    this.sleepStart,
    this.sleepEnd,
    required this.dateLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = duration > 0;
    final hours = duration.floor();
    final mins = ((duration - hours) * 60).round();

    return Container(
      padding: const EdgeInsets.all(20),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.sleep.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bedtime_rounded,
                  color: AppColors.sleep,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    hasData ? '${hours}h ${mins}m' : '-- h -- m',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.sleep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (hasData) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TimeInfo(
                      label: 'Bedtime',
                      time: sleepStart,
                      icon: Icons.bedtime_outlined,
                      iconColor: AppColors.sleepDeep,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  Expanded(
                    child: _TimeInfo(
                      label: 'Wake up',
                      time: sleepEnd,
                      icon: Icons.wb_sunny_outlined,
                      iconColor: AppColors.sleepREM,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    radius: 45,
                  ),
                  PieChartSectionData(
                    value: lightMinutes.toDouble(),
                    color: AppColors.sleepLight,
                    title: '${(lightMinutes / total * 100).round()}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    radius: 45,
                  ),
                  PieChartSectionData(
                    value: remMinutes.toDouble(),
                    color: AppColors.sleepREM,
                    title: '${(remMinutes / total * 100).round()}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    radius: 45,
                  ),
                  PieChartSectionData(
                    value: awakeMinutes.toDouble(),
                    color: AppColors.sleepAwake,
                    title: '${(awakeMinutes / total * 100).round()}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
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
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

// ─── Sleep Timeline ──────────────────────────────

class _SleepTimelineCard extends StatelessWidget {
  final List<Map<String, dynamic>> historyData;
  final DateTime? sleepStart;
  final DateTime? sleepEnd;
  final bool isDark;

  const _SleepTimelineCard({
    required this.historyData,
    this.sleepStart,
    this.sleepEnd,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Filter sleep records only
    final sleepRecords = historyData.where((r) {
      final st = r['sleepType'];
      return st != null && st is int && st > 0;
    }).toList();

    if (sleepRecords.isEmpty) return const SizedBox.shrink();

    final timeFormat = DateFormat('h:mm a');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(color: AppColors.sleep.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sleep Timeline',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                '${sleepRecords.length} data points',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sleepStart != null ? timeFormat.format(sleepStart!) : 'Bedtime',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sleepDeep,
                ),
              ),
              Text(
                sleepEnd != null ? timeFormat.format(sleepEnd!) : 'Wake up',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sleepREM,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Row(
              children: sleepRecords.map((r) {
                final sleepType = r['sleepType'] as int;
                Color color;
                // SDK sleep type: 1=Awake, 2=Light, 3=Deep, 4=REM
                switch (sleepType) {
                  case 1:
                    color = AppColors.sleepAwake;
                    break;
                  case 2:
                    color = AppColors.sleepLight;
                    break;
                  case 3:
                    color = AppColors.sleepDeep;
                    break;
                  case 4:
                    color = AppColors.sleepREM;
                    break;
                  default:
                    color = Colors.grey;
                }
                // Height reflects sleep depth: Deep tallest, Awake shortest
                final heightFactor = sleepType == 3
                    ? 1.0
                    : sleepType == 4
                    ? 0.75
                    : sleepType == 2
                    ? 0.5
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
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
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
            activeTrackColor: AppColors.sleepREM,
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
        border: Border.all(color: AppColors.sleepREM.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'REM Audio Cue',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: AppColors.sleepREM,
                ),
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
                          color: sound == selectedSound
                              ? AppColors.sleepREM
                              : Colors.grey,
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.sleepREM,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(isPlaying ? 'Playing...' : 'Test Sound'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.sleepREM,
                side: BorderSide(
                  color: AppColors.sleepREM.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
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
        border: Border.all(color: AppColors.sleepREM.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.sleepREM,
                size: 20,
              ),
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
            description:
                'The ring monitors your sleep stages in real-time using PPG sensors.',
            color: AppColors.sleepDeep,
          ),
          _StepItem(
            step: '2',
            title: 'REM Detection',
            description:
                'When REM sleep is detected, the app prepares an audio cue.',
            color: AppColors.sleepREM,
          ),
          _StepItem(
            step: '3',
            title: 'Gentle Audio Trigger',
            description:
                'A subtle sound plays, just loud enough to enter your dream without waking you.',
            color: AppColors.sleepLight,
          ),
          _StepItem(
            step: '4',
            title: 'Become Aware',
            description:
                'The audio becomes a cue in your dream, triggering lucid awareness.',
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
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Time Info Widget ────────────────────────────

class _TimeInfo extends StatelessWidget {
  final String label;
  final DateTime? time;
  final IconData icon;
  final Color iconColor;

  const _TimeInfo({
    required this.label,
    this.time,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('h:mm a');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: iconColor.withValues(alpha: 0.8),
              ),
            ),
            Text(
              time != null ? timeFormat.format(time!) : '--:--',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Date Navigator Widget ───────────────────────

class _DateNavigator extends StatelessWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  const _DateNavigator({
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentDate = selectedDate ?? today;

    final daysBack = today.difference(currentDate).inDays;
    final canGoBack = daysBack < 30;
    final canGoForward = currentDate.isBefore(today);

    String dateLabel;
    if (_isSameDay(currentDate, today)) {
      dateLabel = 'Today';
    } else if (_isSameDay(
      currentDate,
      today.subtract(const Duration(days: 1)),
    )) {
      dateLabel = 'Yesterday';
    } else {
      dateLabel = DateFormat('EEE, MMM d').format(currentDate);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(color: AppColors.sleep.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoBack
                ? () => onDateChanged(
                    currentDate.subtract(const Duration(days: 1)),
                  )
                : null,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: canGoBack
                  ? AppColors.sleep
                  : Colors.grey.withValues(alpha: 0.3),
            ),
            tooltip: 'Previous day',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 24,
          ),

          Expanded(
            child: InkWell(
              onTap: () => _showDatePicker(context, currentDate),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.sleep,
                              fontSize: 15,
                            ),
                      ),
                      Text(
                        DateFormat('MMM d, yyyy').format(currentDate),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          IconButton(
            onPressed: canGoForward
                ? () => onDateChanged(currentDate.add(const Duration(days: 1)))
                : null,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: canGoForward
                  ? AppColors.sleep
                  : Colors.grey.withValues(alpha: 0.3),
            ),
            tooltip: 'Next day',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 24,
          ),

          if (!_isSameDay(currentDate, today))
            IconButton(
              onPressed: () => onDateChanged(today),
              icon: const Icon(Icons.today_rounded),
              tooltip: 'Today',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              iconSize: 20,
              color: AppColors.sleep,
            ),
        ],
      ),
    );
  }

  Future<void> _showDatePicker(
    BuildContext context,
    DateTime currentDate,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.sleep,
              onPrimary: Colors.white,
              surface: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.cardDark
                  : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      onDateChanged(picked);
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ─── Log Viewer Sheet ────────────────────────────

class _LogViewerSheet extends StatelessWidget {
  final List<SleepSession> sessions;
  final String logPath;

  const _LogViewerSheet({required this.sessions, required this.logPath});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sleep Data Log',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded),
                  tooltip: 'Share log',
                  onPressed: () {
                    // Share functionality would go here
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bedtime_outlined,
                          size: 48,
                          color: Colors.grey.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No sleep sessions recorded yet',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[sessions.length - 1 - index];
                      return _SessionLogCard(session: session, isDark: isDark);
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Log file: $logPath',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionLogCard extends StatelessWidget {
  final SleepSession session;
  final bool isDark;

  const _SessionLogCard({required this.session, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? AppColors.cardDark : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMM d, yyyy').format(session.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${session.durationHours.toStringAsFixed(1)}h',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.sleep,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StageBadge('Deep', session.deepMinutes, AppColors.sleepDeep),
                const SizedBox(width: 8),
                _StageBadge(
                  'Light',
                  session.lightMinutes,
                  AppColors.sleepLight,
                ),
                const SizedBox(width: 8),
                _StageBadge('REM', session.remMinutes, AppColors.sleepREM),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${session.records.length} records',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final String label;
  final int minutes;
  final Color color;

  const _StageBadge(this.label, this.minutes, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${minutes}m',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
