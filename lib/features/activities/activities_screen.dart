import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/health_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';

class Activity {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int defaultDuration;
  final List<String> metrics;
  final String category;

  const Activity({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.defaultDuration,
    required this.metrics,
    required this.category,
  });
}

// Complete activity library organized by category
final List<Activity> mindfulnessActivities = [
  const Activity(
    id: 'body_scan',
    title: 'Guided Body Scan',
    subtitle: 'Relax each body part sequentially',
    icon: Icons.self_improvement_rounded,
    color: Color(0xFF6B4EFF),
    defaultDuration: 15,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Mindfulness',
  ),
  const Activity(
    id: 'vipassana',
    title: 'Vipassana Meditation',
    subtitle: 'Observe breath and sensations without judgment',
    icon: Icons.bubble_chart_rounded,
    color: Color(0xFF9C27B0),
    defaultDuration: 30,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Mindfulness',
  ),
  const Activity(
    id: 'zen',
    title: 'Zen Meditation',
    subtitle: 'Zazen - seated meditation practice',
    icon: Icons.spa_rounded,
    color: Color(0xFF3F51B5),
    defaultDuration: 20,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Mindfulness',
  ),
  const Activity(
    id: 'metta',
    title: 'Loving-Kindness (Metta)',
    subtitle: 'Cultivate compassion for self and others',
    icon: Icons.favorite_rounded,
    color: Color(0xFFE91E63),
    defaultDuration: 15,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Mindfulness',
  ),
  const Activity(
    id: 'mindful_walking',
    title: 'Mindful Walking',
    subtitle: 'Slow, aware steps in nature or indoors',
    icon: Icons.directions_walk_rounded,
    color: Color(0xFF4CAF50),
    defaultDuration: 20,
    metrics: ['Steps', 'Heart Rate', 'HRV'],
    category: 'Mindfulness',
  ),
  const Activity(
    id: 'open_awareness',
    title: 'Open Awareness',
    subtitle: 'Rest in open, spacious presence',
    icon: Icons.visibility_rounded,
    color: Color(0xFF00BCD4),
    defaultDuration: 20,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Mindfulness',
  ),
];

final List<Activity> breathworkActivities = [
  const Activity(
    id: 'breathing_478',
    title: '4-7-8 Breathing',
    subtitle: 'Inhale 4s, hold 7s, exhale 8s',
    icon: Icons.air_rounded,
    color: Color(0xFF2196F3),
    defaultDuration: 5,
    metrics: ['Heart Rate', 'HRV'],
    category: 'Breathwork',
  ),
  const Activity(
    id: 'box_breathing',
    title: 'Box Breathing',
    subtitle: '4s each: inhale/hold/exhale/hold',
    icon: Icons.square_outlined,
    color: Color(0xFF673AB7),
    defaultDuration: 10,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Breathwork',
  ),
  const Activity(
    id: 'coherent_breathing',
    title: 'Coherent Breathing',
    subtitle: '~5-6 breaths/min slow cycle',
    icon: Icons.waves_rounded,
    color: Color(0xFF009688),
    defaultDuration: 10,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Breathwork',
  ),
  const Activity(
    id: 'wim_hof',
    title: 'Wim Hof Method',
    subtitle: 'Deep breathing + cold exposure prep',
    icon: Icons.ac_unit_rounded,
    color: Color(0xFF00BCD4),
    defaultDuration: 15,
    metrics: ['Heart Rate', 'HRV', 'SpO2'],
    category: 'Breathwork',
  ),
  const Activity(
    id: 'alternate_nostril',
    title: 'Nadi Shodhana',
    subtitle: 'Alternate nostril breathing',
    icon: Icons.sync_alt_rounded,
    color: Color(0xFF7C4DFF),
    defaultDuration: 10,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Breathwork',
  ),
  const Activity(
    id: 'buteyko',
    title: 'Buteyko Method',
    subtitle: 'Gentle nasal breathing',
    icon: Icons.face_rounded,
    color: Color(0xFF795548),
    defaultDuration: 15,
    metrics: ['SpO2', 'Heart Rate'],
    category: 'Breathwork',
  ),
];

final List<Activity> fitnessActivities = [
  const Activity(
    id: 'running',
    title: 'Running / Jogging',
    subtitle: 'Steady pace cardio workout',
    icon: Icons.directions_run_rounded,
    color: Color(0xFFFF9800),
    defaultDuration: 30,
    metrics: ['Heart Rate', 'Steps', 'HRV'],
    category: 'Fitness',
  ),
  const Activity(
    id: 'cycling',
    title: 'Cycling',
    subtitle: 'Road or stationary bike',
    icon: Icons.pedal_bike_rounded,
    color: Color(0xFF4CAF50),
    defaultDuration: 45,
    metrics: ['Heart Rate', 'HRV', 'Steps'],
    category: 'Fitness',
  ),
  const Activity(
    id: 'yoga',
    title: 'Yoga Flow',
    subtitle: 'Vinyasa or Hatha practice',
    icon: Icons.accessibility_new_rounded,
    color: Color(0xFF9C27B0),
    defaultDuration: 45,
    metrics: ['Movement', 'Heart Rate', 'HRV'],
    category: 'Fitness',
  ),
  const Activity(
    id: 'stretching',
    title: 'Light Stretching',
    subtitle: 'Gentle mobility work',
    icon: Icons.pan_tool_rounded,
    color: Color(0xFF009688),
    defaultDuration: 15,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Fitness',
  ),
  const Activity(
    id: 'hiit',
    title: 'HIIT Workout',
    subtitle: 'High intensity interval training',
    icon: Icons.timer_rounded,
    color: Color(0xFFF44336),
    defaultDuration: 20,
    metrics: ['Heart Rate', 'HRV'],
    category: 'Fitness',
  ),
  const Activity(
    id: 'strength',
    title: 'Strength Training',
    subtitle: 'Weights or bodyweight exercises',
    icon: Icons.fitness_center_rounded,
    color: Color(0xFF795548),
    defaultDuration: 45,
    metrics: ['Heart Rate', 'HRV'],
    category: 'Fitness',
  ),
  const Activity(
    id: 'pilates',
    title: 'Pilates',
    subtitle: 'Core strength & flexibility',
    icon: Icons.sports_gymnastics_rounded,
    color: Color(0xFFFFC107),
    defaultDuration: 45,
    metrics: ['Movement', 'Heart Rate', 'HRV'],
    category: 'Fitness',
  ),
  const Activity(
    id: 'dancing',
    title: 'Dancing',
    subtitle: 'Free movement to music',
    icon: Icons.music_note_rounded,
    color: Color(0xFFFF5722),
    defaultDuration: 30,
    metrics: ['Heart Rate', 'Steps', 'HRV'],
    category: 'Fitness',
  ),
];

final List<Activity> waterActivities = [
  const Activity(
    id: 'swimming',
    title: 'Swimming',
    subtitle: 'Pool or open water swimming',
    icon: Icons.pool_rounded,
    color: Color(0xFF2196F3),
    defaultDuration: 30,
    metrics: ['Heart Rate', 'HRV'],
    category: 'Water Sports',
  ),
  const Activity(
    id: 'cold_plunge',
    title: 'Cold Plunge',
    subtitle: 'Ice bath or cold shower therapy',
    icon: Icons.water_drop_rounded,
    color: Color(0xFF03A9F4),
    defaultDuration: 3,
    metrics: ['Heart Rate', 'HRV'],
    category: 'Water Sports',
  ),
];

final List<Activity> intimacyActivities = [
  const Activity(
    id: 'intimacy',
    title: 'Intimacy',
    subtitle: 'Physical connection & bonding',
    icon: Icons.favorite_border_rounded,
    color: Color(0xFFE91E63),
    defaultDuration: 30,
    metrics: ['Heart Rate', 'HRV', 'Calories'],
    category: 'Intimacy',
  ),
  const Activity(
    id: 'cuddle',
    title: 'Cuddling',
    subtitle: 'Physical closeness & oxytocin boost',
    icon: Icons.people_rounded,
    color: Color(0xFFF48FB1),
    defaultDuration: 20,
    metrics: ['Heart Rate', 'HRV'],
    category: 'Intimacy',
  ),
  const Activity(
    id: 'massage',
    title: 'Sensual Massage',
    subtitle: 'Giving or receiving massage',
    icon: Icons.back_hand_rounded,
    color: Color(0xFFCE93D8),
    defaultDuration: 30,
    metrics: ['Heart Rate', 'HRV'],
    category: 'Intimacy',
  ),
];

final List<Activity> sleepActivities = [
  const Activity(
    id: 'sleep_prep',
    title: 'Sleep Preparation',
    subtitle: 'Wind down routine for better sleep',
    icon: Icons.bedtime_rounded,
    color: Color(0xFF3F51B5),
    defaultDuration: 15,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Sleep',
  ),
  const Activity(
    id: 'power_nap',
    title: 'Power Nap',
    subtitle: '20-min restorative rest',
    icon: Icons.nightlight_rounded,
    color: Color(0xFF5C6BC0),
    defaultDuration: 20,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Sleep',
  ),
  const Activity(
    id: 'yoga_nidra',
    title: 'Yoga Nidra',
    subtitle: 'Guided sleep meditation',
    icon: Icons.bedtime_rounded,
    color: Color(0xFF7986CB),
    defaultDuration: 30,
    metrics: ['HRV', 'Heart Rate'],
    category: 'Sleep',
  ),
];

class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  void _goBackOrHome(BuildContext context) {
    if (GoRouter.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.screenGradient(isDark)),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        onPressed: () => _goBackOrHome(context),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Activities',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Mindfulness Section
              _buildSectionHeader(context, 'Mindfulness', isDark),
              _buildActivityList(context, mindfulnessActivities, isDark),

              // Breathwork Section
              _buildSectionHeader(context, 'Breathwork', isDark),
              _buildActivityList(context, breathworkActivities, isDark),

              // Fitness & Movement Section
              _buildSectionHeader(context, 'Fitness & Movement', isDark),
              _buildActivityList(context, fitnessActivities, isDark),

              // Water Sports Section
              _buildSectionHeader(context, 'Water Sports', isDark),
              _buildActivityList(context, waterActivities, isDark),

              // Intimacy & Connection Section
              _buildSectionHeader(context, 'Intimacy & Connection', isDark),
              _buildActivityList(context, intimacyActivities, isDark),

              // Sleep Preparation Section
              _buildSectionHeader(context, 'Sleep Preparation', isDark),
              _buildActivityList(context, sleepActivities, isDark),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, bool isDark) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
          ),
        ),
      ),
    );
  }

  Widget _buildActivityList(
    BuildContext context,
    List<Activity> activities,
    bool isDark,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final activity = activities[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ActivityCard(
              activity: activity,
              isDark: isDark,
              onTap: () => _startActivity(context, activity),
            ),
          );
        }, childCount: activities.length),
      ),
    );
  }

  void _startActivity(BuildContext context, Activity activity) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ActivitySessionSheet(activity: activity),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Activity activity;
  final bool isDark;
  final VoidCallback onTap;

  const _ActivityCard({
    required this.activity,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(color: activity.color.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: activity.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(activity.icon, color: activity.color, size: 24),
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    activity.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activity.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Duration and metrics row
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 12,
                        color: activity.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${activity.defaultDuration} min',
                        style: TextStyle(
                          fontSize: 11,
                          color: activity.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Metrics - wrap in Flexible to prevent overflow
                      Flexible(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: activity.metrics
                              .take(2)
                              .map(
                                (m) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: activity.color.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    m,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: activity.color,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Arrow
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white24 : Colors.black26,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// Activity Session Sheet - Fully Responsive
class ActivitySessionSheet extends ConsumerStatefulWidget {
  final Activity activity;

  const ActivitySessionSheet({super.key, required this.activity});

  @override
  ConsumerState<ActivitySessionSheet> createState() =>
      _ActivitySessionSheetState();
}

class _ActivitySessionSheetState extends ConsumerState<ActivitySessionSheet> {
  late int _durationMinutes;
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _timer;
  int _elapsedSeconds = 0;

  final List<Map<String, dynamic>> _hrData = [];
  final List<Map<String, dynamic>> _hrvData = [];

  @override
  void initState() {
    super.initState();
    _durationMinutes = widget.activity.defaultDuration;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startSession() {
    setState(() {
      _isRunning = true;
      _isPaused = false;
    });

    RingPlugin.startHeartRate();

    RingPlugin.rawHealthData.listen((data) {
      if (data['type'] == 'heartRate') {
        final hr = data['heartRate'] as int? ?? 0;
        final hrv = data['hrv'] as int? ?? 0;
        if (hr > 0 && mounted) {
          setState(() {
            _hrData.add({'time': _elapsedSeconds, 'value': hr});
            if (hrv > 0) _hrvData.add({'time': _elapsedSeconds, 'value': hrv});
          });
        }
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && mounted) {
        setState(() {
          _elapsedSeconds++;
        });

        if (_elapsedSeconds >= _durationMinutes * 60) {
          _completeSession();
        }
      }
    });
  }

  void _pauseSession() {
    setState(() {
      _isPaused = !_isPaused;
    });
  }

  void _stopSession() {
    _timer?.cancel();
    RingPlugin.stopHeartRate();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text('Your progress will be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _completeSession();
            },
            child: const Text('End'),
          ),
        ],
      ),
    );
  }

  void _completeSession() {
    _timer?.cancel();
    RingPlugin.stopHeartRate();

    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SessionSummarySheet(
        activity: widget.activity,
        duration: _elapsedSeconds,
        hrData: _hrData,
        hrvData: _hrvData,
      ),
    );
  }

  String get _timeDisplay {
    final totalSeconds = _durationMinutes * 60 - _elapsedSeconds;
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final currentHR = ref.watch(heartRateProvider)['heartRate'] as int? ?? 0;
    final currentHRV = ref.watch(heartRateProvider)['hrv'] as int? ?? 0;

    final maxHeight = size.height - padding.top - 20;
    final sheetHeight = min(maxHeight * 0.9, 650.0);

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.activity.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            Expanded(
              child: !_isRunning
                  ? _buildDurationSelector(isDark)
                  : _buildActiveSession(isDark, currentHR, currentHRV),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSelector(bool isDark) {
    final durations = [3, 5, 10, 15, 20, 30, 45, 60];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'Select Duration',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),

          // Responsive duration chips using Wrap
          Wrap(
            spacing: 8,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: durations.map((mins) {
              final isSelected = _durationMinutes == mins;
              return ChoiceChip(
                label: Text('${mins}m'),
                selected: isSelected,
                onSelected: (_) => setState(() => _durationMinutes = mins),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : null,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              );
            }).toList(),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startSession,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Session'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildActiveSession(bool isDark, int currentHR, int currentHRV) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Timer - FittedBox prevents overflow
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _timeDisplay,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 72,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Live metrics - Responsive layout
              if (isNarrow)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.activity.metrics.contains('Heart Rate'))
                      _LiveMetricCard(
                        label: 'Heart Rate',
                        value: currentHR > 0 ? '$currentHR' : '--',
                        unit: 'BPM',
                        color: AppColors.heartRate,
                      ),
                    const SizedBox(height: 12),
                    if (widget.activity.metrics.contains('HRV'))
                      _LiveMetricCard(
                        label: 'HRV',
                        value: currentHRV > 0 ? '$currentHRV' : '--',
                        unit: 'ms',
                        color: AppColors.sleepREM,
                      ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.activity.metrics.contains('Heart Rate'))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _LiveMetricCard(
                          label: 'Heart Rate',
                          value: currentHR > 0 ? '$currentHR' : '--',
                          unit: 'BPM',
                          color: AppColors.heartRate,
                        ),
                      ),
                    if (widget.activity.metrics.contains('HRV'))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _LiveMetricCard(
                          label: 'HRV',
                          value: currentHRV > 0 ? '$currentHRV' : '--',
                          unit: 'ms',
                          color: AppColors.sleepREM,
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 48),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.large(
                    heroTag: 'pause',
                    onPressed: _pauseSession,
                    backgroundColor: AppColors.primary,
                    child: Icon(
                      _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 32),
                  FloatingActionButton.large(
                    heroTag: 'stop',
                    onPressed: _stopSession,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.stop_rounded, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

class _LiveMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _LiveMetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Text(unit, style: TextStyle(fontSize: 14, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// Session Summary Sheet - Responsive
class _SessionSummarySheet extends StatelessWidget {
  final Activity activity;
  final int duration;
  final List<Map<String, dynamic>> hrData;
  final List<Map<String, dynamic>> hrvData;

  const _SessionSummarySheet({
    required this.activity,
    required this.duration,
    required this.hrData,
    required this.hrvData,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avgHR = hrData.isNotEmpty
        ? hrData.map((e) => e['value'] as int).reduce((a, b) => a + b) ~/
              hrData.length
        : 0;
    final avgHRV = hrvData.isNotEmpty
        ? hrvData.map((e) => e['value'] as int).reduce((a, b) => a + b) ~/
              hrvData.length
        : 0;
    final mins = duration ~/ 60;
    final secs = duration % 60;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 56,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Session Complete!',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      activity.title,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Stats grid - adaptive layout
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 340;

                        return Column(
                          children: [
                            if (isNarrow)
                              Column(
                                children: [
                                  _SummaryStatFull(
                                    label: 'Duration',
                                    value: '${mins}m ${secs}s',
                                    icon: Icons.timer_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  _SummaryStatFull(
                                    label: 'Avg Heart Rate',
                                    value: avgHR > 0 ? '$avgHR BPM' : '--',
                                    icon: Icons.favorite_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  _SummaryStatFull(
                                    label: 'Avg HRV',
                                    value: avgHRV > 0 ? '$avgHRV ms' : '--',
                                    icon: Icons.trending_up_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  _SummaryStatFull(
                                    label: 'Data Points',
                                    value: '${hrData.length}',
                                    icon: Icons.analytics_rounded,
                                  ),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      _SummaryStat(
                                        label: 'Duration',
                                        value: '${mins}m ${secs}s',
                                        icon: Icons.timer_rounded,
                                      ),
                                      _SummaryStat(
                                        label: 'Avg Heart Rate',
                                        value: avgHR > 0 ? '$avgHR BPM' : '--',
                                        icon: Icons.favorite_rounded,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _SummaryStat(
                                        label: 'Avg HRV',
                                        value: avgHRV > 0 ? '$avgHRV ms' : '--',
                                        icon: Icons.trending_up_rounded,
                                      ),
                                      _SummaryStat(
                                        label: 'Data Points',
                                        value: '${hrData.length}',
                                        icon: Icons.analytics_rounded,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SummaryStatFull extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryStatFull({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
