import 'dart:async';
import 'dart:math' show sin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/health_provider.dart';
import '../../providers/ring_provider.dart';

// Re-export timestamp providers from health_provider for convenience

import '../../plugins/ring_sdk/ring_plugin.dart';



/// Waveform animation providers for each vital
final hrWaveformProvider = StateProvider<List<double>>((ref) => []);
final spo2WaveformProvider = StateProvider<List<double>>((ref) => []);
final tempWaveformProvider = StateProvider<List<double>>((ref) => []);

/// Cool-off duration between consecutive measurements (30 seconds)
const _coolOffDuration = Duration(seconds: 30);

/// Provider that tracks if any vital measurement is currently in progress
final anyMeasurementInProgressProvider = Provider<bool>((ref) {
  return ref.watch(heartRateMeasuringProvider) ||
      ref.watch(spo2MeasuringProvider) ||
      ref.watch(temperatureMeasuringProvider) ||
      ref.watch(bpMeasuringProvider);
});

class VitalsScreen extends ConsumerStatefulWidget {
  const VitalsScreen({super.key});

  @override
  ConsumerState<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends ConsumerState<VitalsScreen> {
  // Safety timeouts to prevent spinner from spinning forever
  Timer? _hrTimeout;
  Timer? _spo2Timeout;
  Timer? _tempTimeout;
  Timer? _bpTimeout;
  
  // Waveform animation timers
  Timer? _hrWaveformTimer;
  Timer? _spo2WaveformTimer;
  Timer? _tempWaveformTimer;
  Timer? _bpWaveformTimer;
  
  static const _safetyTimeout = Duration(seconds: 30);
  static const _bpSafetyTimeout = Duration(seconds: 60);

  @override
  void dispose() {
    _hrTimeout?.cancel();
    _spo2Timeout?.cancel();
    _tempTimeout?.cancel();
    _bpTimeout?.cancel();
    _hrWaveformTimer?.cancel();
    _spo2WaveformTimer?.cancel();
    _tempWaveformTimer?.cancel();
    _bpWaveformTimer?.cancel();
    super.dispose();
  }

  void _startSafetyTimeout(String type) {
    debugPrint('[VitalsScreen] Starting $type measurement safety timeout');
    switch (type) {
      case 'hr':
        _hrTimeout?.cancel();
        _hrTimeout = Timer(_safetyTimeout, () {
          debugPrint('[VitalsScreen] HR safety timeout - resetting measuring state');
          if (mounted) {
            ref.read(heartRateMeasuringProvider.notifier).state = false;
            _stopHrWaveform();
          }
        });
        break;
      case 'spo2':
        _spo2Timeout?.cancel();
        _spo2Timeout = Timer(_safetyTimeout, () {
          debugPrint('[VitalsScreen] SpO2 safety timeout - resetting measuring state');
          if (mounted) {
            ref.read(spo2MeasuringProvider.notifier).state = false;
            _stopSpo2Waveform();
          }
        });
        break;
      case 'temp':
        _tempTimeout?.cancel();
        _tempTimeout = Timer(_safetyTimeout, () {
          debugPrint('[VitalsScreen] Temperature safety timeout - resetting measuring state');
          if (mounted) {
            ref.read(temperatureMeasuringProvider.notifier).state = false;
            _stopTempWaveform();
          }
        });
        break;
      case 'bp':
        _bpTimeout?.cancel();
        _bpTimeout = Timer(_bpSafetyTimeout, () {
          debugPrint('[VitalsScreen] BP safety timeout - resetting measuring state');
          if (mounted) {
            ref.read(bpMeasuringProvider.notifier).state = false;
          }
        });
        break;
    }
  }

  void _cancelSafetyTimeout(String type) {
    debugPrint('[VitalsScreen] Canceling $type safety timeout');
    switch (type) {
      case 'hr':
        _hrTimeout?.cancel();
        break;
      case 'spo2':
        _spo2Timeout?.cancel();
        break;
      case 'temp':
        _tempTimeout?.cancel();
        break;
      case 'bp':
        _bpTimeout?.cancel();
        break;
    }
  }

  // Waveform animation generators
  void _startHrWaveform() {
    _hrWaveformTimer?.cancel();
    double t = 0;
    _hrWaveformTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      t += 0.15;
      final waveform = ref.read(hrWaveformProvider);
      final newValue = sin(t) * 0.3 + sin(t * 2.5) * 0.15 + (Random().nextDouble() - 0.5) * 0.1;
      final newWaveform = [...waveform, newValue];
      if (newWaveform.length > 60) newWaveform.removeAt(0);
      ref.read(hrWaveformProvider.notifier).state = newWaveform;
    });
  }

  void _stopHrWaveform() {
    _hrWaveformTimer?.cancel();
    ref.read(hrWaveformProvider.notifier).state = [];
  }

  void _startSpo2Waveform() {
    _spo2WaveformTimer?.cancel();
    double t = 0;
    _spo2WaveformTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      t += 0.12;
      final waveform = ref.read(spo2WaveformProvider);
      final newValue = sin(t) * 0.25 + sin(t * 3) * 0.1 + 0.5;
      final newWaveform = [...waveform, newValue];
      if (newWaveform.length > 60) newWaveform.removeAt(0);
      ref.read(spo2WaveformProvider.notifier).state = newWaveform;
    });
  }

  void _stopSpo2Waveform() {
    _spo2WaveformTimer?.cancel();
    ref.read(spo2WaveformProvider.notifier).state = [];
  }

  void _startTempWaveform() {
    _tempWaveformTimer?.cancel();
    double t = 0;
    _tempWaveformTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      t += 0.08;
      final waveform = ref.read(tempWaveformProvider);
      final newValue = sin(t) * 0.15 + (Random().nextDouble() - 0.5) * 0.05;
      final newWaveform = [...waveform, newValue];
      if (newWaveform.length > 40) newWaveform.removeAt(0);
      ref.read(tempWaveformProvider.notifier).state = newWaveform;
    });
  }

  void _stopTempWaveform() {
    _tempWaveformTimer?.cancel();
    ref.read(tempWaveformProvider.notifier).state = [];
  }

  @override
  Widget build(BuildContext context) {
    final hrData = ref.watch(heartRateProvider);
    final hr = hrData['heartRate'] as int? ?? 0;
    final spo2Data = ref.watch(spo2Provider);
    final spo2 = spo2Data['spo2'] as int? ?? 0;
    final temperature = ref.watch(temperatureProvider);
    final systolic = ref.watch(systolicProvider);
    final diastolic = ref.watch(diastolicProvider);
    final hrHistory = ref.watch(heartRateHistoryProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Vitals',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => context.go('/sleep'),
                      icon: const Icon(Icons.bedtime_rounded, size: 18),
                      label: const Text('Sleep'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.sleep,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Heart Rate Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _VitalCardFullWidth(
                  title: 'Heart Rate',
                  subtitle: 'BPM',
                  value: hr > 0 ? '$hr' : '--',
                  unit: 'BPM',
                  icon: Icons.favorite_rounded,
                  iconColor: AppColors.heartRate,
                  iconGradient: [const Color(0xFFFF6B6B), const Color(0xFFFF8E8E)],
                  status: _getHRZone(hr),
                  isActive: hr > 0,
                  lastScanTime: ref.watch(heartRateLastScanProvider),
                  onMeasure: _toggleHeartRate,
                  isMeasuring: ref.watch(heartRateMeasuringProvider),
                  waveformData: ref.watch(hrWaveformProvider),
                  historyData: hrHistory,
                  isAnyMeasuring: ref.watch(anyMeasurementInProgressProvider),
                ),
              ),
            ),

            // SpO2 Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _VitalCardFullWidth(
                  title: 'Blood Oxygen',
                  subtitle: 'SpO2',
                  value: spo2 > 0 ? '$spo2' : '--',
                  unit: '%',
                  icon: Icons.water_drop_rounded,
                  iconColor: AppColors.spo2,
                  iconGradient: [const Color(0xFF4ECDC4), const Color(0xFF6EE7DE)],
                  status: spo2 >= 95 ? 'Normal' : (spo2 > 0 ? 'Low' : 'Not measured'),
                  isActive: spo2 > 0,
                  statusColor: spo2 >= 95 ? AppColors.success : (spo2 > 0 ? AppColors.warning : null),
                  lastScanTime: ref.watch(spo2LastScanProvider),
                  onMeasure: _toggleSpO2,
                  isMeasuring: ref.watch(spo2MeasuringProvider),
                  waveformData: ref.watch(spo2WaveformProvider),
                  isAnyMeasuring: ref.watch(anyMeasurementInProgressProvider),
                ),
              ),
            ),

            // Temperature Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _VitalCardFullWidth(
                  title: 'Body Temperature',
                  subtitle: 'Temperature',
                  value: temperature > 0 ? temperature.toStringAsFixed(1) : '--',
                  unit: '°C',
                  icon: Icons.thermostat_rounded,
                  iconColor: AppColors.temperature,
                  iconGradient: [const Color(0xFFFFA726), const Color(0xFFFFB74D)],
                  status: temperature > 0 ? _getTempCategory(temperature) : 'Not measured',
                  isActive: temperature > 0,
                  lastScanTime: ref.watch(temperatureLastScanProvider),
                  onMeasure: _toggleTemperature,
                  isMeasuring: ref.watch(temperatureMeasuringProvider),
                  waveformData: ref.watch(tempWaveformProvider),
                  isAnyMeasuring: ref.watch(anyMeasurementInProgressProvider),
                ),
              ),
            ),

            // Blood Pressure Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: _VitalCardFullWidth(
                  title: 'Blood Pressure',
                  subtitle: 'PPG-based measurement',
                  value: systolic > 0 && diastolic > 0 ? '$systolic/$diastolic' : '--/--',
                  unit: 'mmHg',
                  icon: Icons.speed_rounded,
                  iconColor: AppColors.bloodPressure,
                  iconGradient: [const Color(0xFFFF9F43), const Color(0xFFFFB366)],
                  status: systolic > 0 ? _getBPCategory(systolic, diastolic) : 'Ready to measure',
                  isActive: systolic > 0,
                  lastScanTime: ref.watch(bpLastScanProvider),
                  onMeasure: _toggleBloodPressure,
                  isMeasuring: ref.watch(bpMeasuringProvider),
                  waveformData: ref.watch(ppgWaveformProvider),
                  isAnyMeasuring: ref.watch(anyMeasurementInProgressProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleHeartRate() {
    final isMeasuring = ref.read(heartRateMeasuringProvider);
    if (isMeasuring) {
      _cancelSafetyTimeout('hr');
      RingPlugin.stopHeartRate();
      ref.read(heartRateMeasuringProvider.notifier).state = false;
      _stopHrWaveform();
    } else {
      _startSafetyTimeout('hr');
      RingPlugin.startHeartRate();
      ref.read(heartRateMeasuringProvider.notifier).state = true;
      _startHrWaveform();
    }
  }

  void _toggleSpO2() {
    final isMeasuring = ref.read(spo2MeasuringProvider);
    if (isMeasuring) {
      _cancelSafetyTimeout('spo2');
      RingPlugin.stopSpO2();
      ref.read(spo2MeasuringProvider.notifier).state = false;
      _stopSpo2Waveform();
    } else {
      _startSafetyTimeout('spo2');
      RingPlugin.startSpO2();
      ref.read(spo2MeasuringProvider.notifier).state = true;
      _startSpo2Waveform();
    }
  }

  void _toggleTemperature() {
    final isMeasuring = ref.read(temperatureMeasuringProvider);
    if (isMeasuring) {
      _cancelSafetyTimeout('temp');
      ref.read(temperatureMeasuringProvider.notifier).state = false;
      RingPlugin.startTemperature(); // Stop measurement
      _stopTempWaveform();
    } else {
      _startSafetyTimeout('temp');
      ref.read(temperatureMeasuringProvider.notifier).state = true;
      RingPlugin.startTemperature();
      _startTempWaveform();
    }
  }

  void _toggleBloodPressure() {
    final isMeasuring = ref.read(bpMeasuringProvider);
    if (isMeasuring) {
      _cancelSafetyTimeout('bp');
      RingPlugin.stopBloodPressure();
      ref.read(bpMeasuringProvider.notifier).state = false;
      ref.read(ppgWaveformProvider.notifier).state = [];
    } else {
      _startSafetyTimeout('bp');
      ref.read(bpMeasuringProvider.notifier).state = true;
      ref.read(bpProgressValueProvider.notifier).state = 0;
      ref.read(ppgWaveformProvider.notifier).state = [];
      RingPlugin.startBloodPressure();
    }
  }

  String _getHRZone(int bpm) {
    if (bpm == 0) return 'Not measured';
    if (bpm < 60) return 'Below resting';
    if (bpm <= 100) return 'Resting zone';
    if (bpm <= 140) return 'Fat burn zone';
    return 'Cardio zone';
  }

  String _getTempCategory(double temp) {
    if (temp < 35.0) return 'Below normal';
    if (temp <= 37.2) return 'Normal range';
    if (temp <= 38.0) return 'Slightly elevated';
    return 'Elevated';
  }

  String _getBPCategory(int sys, int dia) {
    if (sys < 120 && dia < 80) return 'Normal';
    if (sys < 130 && dia < 80) return 'Elevated';
    if (sys < 140 || dia < 90) return 'Stage 1';
    return 'Stage 2';
  }
}

/// Full-width vital card with waveform visualization
class _VitalCardFullWidth extends StatefulWidget {
  final String title;
  final String subtitle;
  final String value;
  final String unit;
  final IconData icon;
  final Color iconColor;
  final List<Color> iconGradient;
  final String status;
  final bool isActive;
  final Color? statusColor;
  final DateTime? lastScanTime;
  final VoidCallback onMeasure;
  final bool isMeasuring;
  final List<double> waveformData;
  final List<double>? historyData;
  final bool isAnyMeasuring;

  const _VitalCardFullWidth({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.unit,
    required this.icon,
    required this.iconColor,
    required this.iconGradient,
    required this.status,
    required this.isActive,
    this.statusColor,
    this.lastScanTime,
    required this.onMeasure,
    required this.isMeasuring,
    required this.waveformData,
    this.historyData,
    required this.isAnyMeasuring,
  });

  @override
  State<_VitalCardFullWidth> createState() => _VitalCardFullWidthState();
}

class _VitalCardFullWidthState extends State<_VitalCardFullWidth> {
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _updateRemainingTime();
    _startCountdownTimer();
  }

  @override
  void didUpdateWidget(_VitalCardFullWidth oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart timer if lastScanTime changes
    if (oldWidget.lastScanTime != widget.lastScanTime) {
      _updateRemainingTime();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final newRemaining = _getRemainingCoolOffSeconds(widget.lastScanTime);
      if (newRemaining != _remainingSeconds) {
        setState(() {
          _remainingSeconds = newRemaining;
        });
      }
    });
  }

  void _updateRemainingTime() {
    _remainingSeconds = _getRemainingCoolOffSeconds(widget.lastScanTime);
  }

  String get title => widget.title;
  String get subtitle => widget.subtitle;
  String get value => widget.value;
  String get unit => widget.unit;
  IconData get icon => widget.icon;
  Color get iconColor => widget.iconColor;
  List<Color> get iconGradient => widget.iconGradient;
  String get status => widget.status;
  bool get isActive => widget.isActive;
  Color? get statusColor => widget.statusColor;
  DateTime? get lastScanTime => widget.lastScanTime;
  VoidCallback get onMeasure => widget.onMeasure;
  bool get isMeasuring => widget.isMeasuring;
  List<double> get waveformData => widget.waveformData;
  List<double>? get historyData => widget.historyData;
  bool get isAnyMeasuring => widget.isAnyMeasuring;

  String _formatLastScan(DateTime? time) {
    if (time == null) return 'Never scanned';
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} days ago';
  }

  /// Returns remaining cool-off time in seconds, 0 if ready
  int _getRemainingCoolOffSeconds(DateTime? lastScan) {
    if (lastScan == null) return 0;
    final elapsed = DateTime.now().difference(lastScan);
    final remaining = _coolOffDuration - elapsed;
    return remaining.inSeconds > 0 ? remaining.inSeconds : 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Button is disabled if:
    // 1. Another measurement is in progress (not this one)
    // 2. Cool-off period hasn't elapsed (and not currently measuring)
    final isDisabled = (!isMeasuring && isAnyMeasuring) || 
                       (!isMeasuring && _remainingSeconds > 0);
    
    // Determine button text and color
    String buttonText;
    Color buttonColor;
    if (isMeasuring) {
      buttonText = 'Stop Scan';
      buttonColor = AppColors.error;
    } else if (isAnyMeasuring) {
      buttonText = 'Busy';
      buttonColor = Colors.grey;
    } else if (_remainingSeconds > 0) {
      buttonText = 'Wait ${_remainingSeconds}s';
      buttonColor = Colors.grey;
    } else {
      buttonText = 'Start Scan';
      buttonColor = iconColor;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: isMeasuring 
              ? iconColor.withValues(alpha: 0.5)
              : isDisabled 
                  ? Colors.grey.withValues(alpha: 0.2)
                  : iconColor.withValues(alpha: 0.15),
          width: isMeasuring ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: isMeasuring ? 0.15 : isDisabled ? 0.02 : 0.08),
            blurRadius: isMeasuring ? 20 : 12,
            offset: const Offset(0, 4),
            spreadRadius: isMeasuring ? 2 : 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        child: Column(
          children: [
            // Main content area
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon with gradient background
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: iconGradient.map((c) => c.withValues(alpha: 0.15)).toList(),
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: isMeasuring
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: iconColor,
                              ),
                            )
                          : Icon(icon, color: iconColor, size: 28),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Title and subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Value display
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            value,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: isActive ? iconColor : (isDark ? Colors.white54 : Colors.black38),
                              fontWeight: FontWeight.w700,
                              fontSize: 32,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            unit,
                            style: TextStyle(
                              color: iconColor.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (statusColor ?? (isActive ? AppColors.success : (isDark ? Colors.white12 : Colors.black12)))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor ?? (isActive ? AppColors.success : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Waveform visualization area - only show when measuring or has history
            if (isMeasuring && waveformData.isNotEmpty)
              Container(
                height: 50,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _AnimatedWaveform(
                  data: waveformData,
                  color: iconColor,
                ),
              )
            else if (!isMeasuring && historyData != null && historyData!.isNotEmpty)
              Container(
                height: 40,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _MiniChart(data: historyData!, color: iconColor),
              ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  // Last scan time
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatLastScan(lastScanTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Scan/Stop button
                  FilledButton.icon(
                    onPressed: isDisabled ? null : onMeasure,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isMeasuring ? Icons.stop_rounded : 
                        isDisabled ? Icons.hourglass_empty_rounded : Icons.play_arrow_rounded,
                        size: 18,
                        key: ValueKey('$isMeasuring-$isDisabled'),
                      ),
                    ),
                    label: Text(
                      buttonText,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      elevation: isMeasuring ? 0 : isDisabled ? 0 : 2,
                      shadowColor: iconColor.withValues(alpha: 0.4),
                      disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                      disabledForegroundColor: Colors.grey.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated waveform widget for live measurements
class _AnimatedWaveform extends StatelessWidget {
  final List<double> data;
  final Color color;

  const _AnimatedWaveform({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 60),
      painter: _WaveformPainter(data: data, color: color),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _WaveformPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();
    
    final stepX = size.width / (data.length - 1);
    final centerY = size.height / 2;
    final amplitude = size.height * 0.4;

    path.moveTo(0, centerY - data[0] * amplitude);
    fillPath.moveTo(0, centerY - data[0] * amplitude);

    for (int i = 1; i < data.length; i++) {
      final x = i * stepX;
      final y = centerY - data[i] * amplitude;
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Mini chart for history data
class _MiniChart extends StatelessWidget {
  final List<double> data;
  final Color color;

  const _MiniChart({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final validData = data.where((v) => v > 0).toList();
    if (validData.isEmpty) return const SizedBox.shrink();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: validData.reduce((a, b) => a < b ? a : b) * 0.9,
        maxY: validData.reduce((a, b) => a > b ? a : b) * 1.1,
        lineBarsData: [
          LineChartBarData(
            spots: validData.asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), e.value);
            }).toList(),
            isCurved: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.3),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple Random class for waveform generation
class Random {
  static final Random _instance = Random._internal();
  factory Random() => _instance;
  Random._internal();
  
  double nextDouble() {
    return (DateTime.now().microsecond % 1000) / 1000;
  }
}
