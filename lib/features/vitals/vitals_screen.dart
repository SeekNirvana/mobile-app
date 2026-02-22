import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/health_provider.dart';
import '../../providers/ring_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';
import '../../services/feature_detection_service.dart';

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
  
  static const _safetyTimeout = Duration(seconds: 30);
  static const _bpSafetyTimeout = Duration(seconds: 60);
  
  // Track if ring is busy
  bool _isRingBusy = false;

  @override
  void initState() {
    super.initState();
    // Listen to RingPlugin's measurement state
    RingPlugin.measurementState.listen((isMeasuring) {
      if (mounted) {
        setState(() {
          _isRingBusy = isMeasuring;
        });
      }
    });
  }

  @override
  void dispose() {
    _hrTimeout?.cancel();
    _spo2Timeout?.cancel();
    _tempTimeout?.cancel();
    _bpTimeout?.cancel();
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
          }
        });
        break;
      case 'spo2':
        _spo2Timeout?.cancel();
        _spo2Timeout = Timer(_safetyTimeout, () {
          debugPrint('[VitalsScreen] SpO2 safety timeout - resetting measuring state');
          if (mounted) {
            ref.read(spo2MeasuringProvider.notifier).state = false;
          }
        });
        break;
      case 'temp':
        _tempTimeout?.cancel();
        _tempTimeout = Timer(_safetyTimeout, () {
          debugPrint('[VitalsScreen] Temperature safety timeout - resetting measuring state');
          if (mounted) {
            ref.read(temperatureMeasuringProvider.notifier).state = false;
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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

            // Heart Rate & SpO2 Row
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _VitalCard(
                        title: 'Heart Rate',
                        value: hr > 0 ? '$hr' : '--',
                        unit: 'BPM',
                        icon: Icons.favorite_rounded,
                        iconColor: AppColors.heartRate,
                        status: _getHRZone(hr),
                        isActive: hr > 0,
                        onMeasure: _toggleHeartRate,
                        isMeasuring: ref.watch(heartRateMeasuringProvider),
                        child: hrHistory.isNotEmpty
                            ? _MiniChart(data: hrHistory, color: AppColors.heartRate)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _VitalCard(
                        title: 'SpO2',
                        value: spo2 > 0 ? '$spo2' : '--',
                        unit: '%',
                        icon: Icons.water_drop_rounded,
                        iconColor: AppColors.spo2,
                        status: spo2 >= 95 ? 'Normal' : (spo2 > 0 ? 'Low' : 'Not measured'),
                        isActive: spo2 > 0,
                        statusColor: spo2 >= 95 ? AppColors.success : (spo2 > 0 ? AppColors.warning : null),
                        onMeasure: _toggleSpO2,
                        isMeasuring: ref.watch(spo2MeasuringProvider),
                        child: spo2 > 0 ? _GaugeIndicator(value: spo2, color: AppColors.spo2) : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Temperature & Blood Pressure Row (conditional)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _VitalCard(
                        title: 'Temperature',
                        value: temperature > 0 ? temperature.toStringAsFixed(1) : '--',
                        unit: '°C',
                        icon: Icons.thermostat_rounded,
                        iconColor: AppColors.temperature,
                        status: temperature > 0 ? _getTempCategory(temperature) : 'Not measured',
                        isActive: temperature > 0,
                        onMeasure: _startTemperature,
                        isMeasuring: ref.watch(temperatureMeasuringProvider),
                      ),
                    ),
                    // Show BP only if supported by ring
                    if (FeatureDetectionService.supportsBloodPressure) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _VitalCard(
                          title: 'Blood Pressure',
                          value: systolic > 0 && diastolic > 0 ? '$systolic/$diastolic' : '--/--',
                          unit: 'mmHg',
                          icon: Icons.speed_rounded,
                          iconColor: AppColors.bloodPressure,
                          status: systolic > 0 ? _getBPCategory(systolic, diastolic) : 'PPG-based',
                          isActive: systolic > 0,
                          onMeasure: _toggleBloodPressure,
                          isMeasuring: ref.watch(bpMeasuringProvider),
                          child: ref.watch(bpMeasuringProvider) && ref.watch(ppgWaveformProvider).isNotEmpty
                              ? _WaveformPreview(data: ref.watch(ppgWaveformProvider), color: AppColors.bloodPressure)
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleHeartRate() async {
    final isMeasuring = ref.read(heartRateMeasuringProvider);
    if (isMeasuring) {
      _cancelSafetyTimeout('hr');
      RingPlugin.stopHeartRate();
      ref.read(heartRateMeasuringProvider.notifier).state = false;
    } else {
      try {
        _startSafetyTimeout('hr');
        await RingPlugin.startHeartRate();
        ref.read(heartRateMeasuringProvider.notifier).state = true;
      } on RingBusyException catch (e) {
        _showBusyError(e.toString());
      }
    }
  }

  void _toggleSpO2() async {
    final isMeasuring = ref.read(spo2MeasuringProvider);
    
    // Check if ring is busy with another measurement
    if (!isMeasuring && _isRingBusy) {
      _showBusySnackBar();
      return;
    }
    
    if (isMeasuring) {
      _cancelSafetyTimeout('spo2');
      await RingPlugin.stopSpO2();
      ref.read(spo2MeasuringProvider.notifier).state = false;
    } else {
      try {
        _startSafetyTimeout('spo2');
        await RingPlugin.startSpO2();
        ref.read(spo2MeasuringProvider.notifier).state = true;
      } on RingBusyException catch (e) {
        _showBusyError(e.toString());
      }
    }
  }

  void _startTemperature() async {
    // Check if ring is busy
    if (_isRingBusy) {
      _showBusySnackBar();
      return;
    }
    
    if (!ref.read(temperatureMeasuringProvider)) {
      try {
        _startSafetyTimeout('temp');
        await RingPlugin.startTemperature();
        ref.read(temperatureMeasuringProvider.notifier).state = true;
      } on RingBusyException catch (e) {
        _showBusyError(e.toString());
      }
    }
  }

  void _toggleBloodPressure() async {
    final isMeasuring = ref.read(bpMeasuringProvider);
    if (isMeasuring) {
      _cancelSafetyTimeout('bp');
      RingPlugin.stopBloodPressure();
      ref.read(bpMeasuringProvider.notifier).state = false;
    } else {
      try {
        _startSafetyTimeout('bp');
        ref.read(bpMeasuringProvider.notifier).state = true;
        ref.read(bpProgressValueProvider.notifier).state = 0;
        ref.read(ppgWaveformProvider.notifier).state = [];
        await RingPlugin.startBloodPressure();
      } on RingBusyException catch (e) {
        _showBusyError(e.toString());
      }
    }
  }
  
  void _showBusySnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 16, 
              height: 16, 
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Ring is busy measuring. Please wait...'),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showBusyError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
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

class _VitalCard extends ConsumerWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color iconColor;
  final String status;
  final bool isActive;
  final Color? statusColor;
  final VoidCallback onMeasure;
  final bool isMeasuring;
  final Widget? child;

  const _VitalCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.iconColor,
    required this.status,
    required this.isActive,
    this.statusColor,
    required this.onMeasure,
    required this.isMeasuring,
    this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isMeasuring
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: iconColor,
                        ),
                      )
                    : Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Value display
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: isActive ? iconColor : (isDark ? Colors.white54 : Colors.black38),
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: iconColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          
          // Status text
          Text(
            status,
            style: TextStyle(
              color: statusColor ?? (isActive ? AppColors.success : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          
          const Spacer(),
          
          // Chart or visual indicator
          if (child != null) ...[
            SizedBox(height: 40, child: child),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 48),
          
          // Measure button
          SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton.icon(
              onPressed: onMeasure,
              icon: Icon(
                isMeasuring ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 16,
              ),
              label: Text(
                isMeasuring ? 'Stop' : 'Measure',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: iconColor,
                side: BorderSide(color: iconColor.withValues(alpha: 0.5)),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

class _GaugeIndicator extends StatelessWidget {
  final int value;
  final Color color;

  const _GaugeIndicator({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            value: value / 100,
            strokeWidth: 4,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
            strokeCap: StrokeCap.round,
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _WaveformPreview extends StatelessWidget {
  final List<double> data;
  final Color color;

  const _WaveformPreview({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final recentData = data.length > 50 ? data.sublist(data.length - 50) : data;
    
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: recentData.reduce((a, b) => a < b ? a : b),
        maxY: recentData.reduce((a, b) => a > b ? a : b),
        lineBarsData: [
          LineChartBarData(
            spots: recentData.asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), e.value);
            }).toList(),
            isCurved: false,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
