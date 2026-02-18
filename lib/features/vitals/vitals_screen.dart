import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/health_provider.dart';
import '../../providers/ring_provider.dart';
import '../../shared/widgets/pulse_animation.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';

class VitalsScreen extends ConsumerWidget {
  const VitalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hrData = ref.watch(heartRateProvider);
    final hr = hrData['heartRate'] as int? ?? 0;
    final spo2Data = ref.watch(spo2Provider);
    final spo2 = spo2Data['spo2'] as int? ?? 0;
    final temperature = ref.watch(temperatureProvider);
    final systolic = ref.watch(systolicProvider);
    final diastolic = ref.watch(diastolicProvider);
    final hrHistory = ref.watch(heartRateHistoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  'Vitals',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            // Heart Rate Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _HeartRateCard(bpm: hr, history: hrHistory, isDark: isDark),
              ),
            ),

            // SpO2 Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _SpO2Card(value: spo2, isDark: isDark),
              ),
            ),

            // Temperature Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _TemperatureCard(value: temperature, isDark: isDark),
              ),
            ),

            // Blood Pressure Section (PPG-based)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: _BloodPressureCard(
                  systolic: systolic,
                  diastolic: diastolic,
                  isDark: isDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartRateCard extends ConsumerWidget {
  final int bpm;
  final List<double> history;
  final bool isDark;

  const _HeartRateCard({
    required this.bpm,
    required this.history,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMeasuring = ref.watch(heartRateMeasuringProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: AppColors.heartRate.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.heartRate.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PulseAnimation(
                color: AppColors.heartRate,
                size: 64,
                bpm: bpm,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Heart Rate',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            '$bpm',
                            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              color: AppColors.heartRate,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'BPM',
                          style: TextStyle(
                            color: AppColors.heartRate.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _getHRZone(bpm),
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                             if (isMeasuring) {
                               RingPlugin.stopHeartRate();
                               ref.read(heartRateMeasuringProvider.notifier).state = false;
                             } else {
                               RingPlugin.startHeartRate();
                               ref.read(heartRateMeasuringProvider.notifier).state = true;
                             }
                          },
                          icon: isMeasuring 
                              ? const SizedBox(
                                  width: 20, 
                                  height: 20, 
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.heartRate)
                                )
                              : const Icon(Icons.play_circle_outline, size: 20),
                          label: Text(isMeasuring ? "Measuring..." : "Measure"),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.heartRate,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 80,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: history.asMap().entries.map((e) {
                      return FlSpot(e.key.toDouble(), e.value);
                    }).toList(),
                    isCurved: true,
                    color: AppColors.heartRate,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.heartRate.withValues(alpha: 0.3),
                          AppColors.heartRate.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getHRZone(int bpm) {
    if (bpm < 60) return 'Below resting';
    if (bpm <= 100) return 'Resting zone';
    if (bpm <= 140) return 'Fat burn zone';
    if (bpm <= 170) return 'Cardio zone';
    return 'Peak zone';
  }
}

class _SpO2Card extends ConsumerWidget {
  final int value;
  final bool isDark;

  const _SpO2Card({required this.value, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMeasuring = ref.watch(spo2MeasuringProvider);
    final isNormal = value >= 95;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: AppColors.spo2.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gauge
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 68,
                  height: 68,
                  child: CircularProgressIndicator(
                    value: value / 100,
                    strokeWidth: 7,
                    backgroundColor: isDark
                        ? AppColors.cardBorderDark
                        : AppColors.cardBorderLight,
                    valueColor: AlwaysStoppedAnimation(
                      isNormal ? AppColors.spo2 : AppColors.spo2Low,
                    ),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Icon(
                  Icons.water_drop_rounded,
                  color: AppColors.spo2,
                  size: 24,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Blood Oxygen (SpO2)',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        '$value',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: isNormal ? AppColors.spo2 : AppColors.spo2Low,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '%',
                      style: TextStyle(
                        color: AppColors.spo2.withValues(alpha: 0.7),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isNormal ? 'Normal range' : 'Below normal',
                      style: TextStyle(
                        color: isNormal ? AppColors.success : AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                         if (isMeasuring) {
                           RingPlugin.stopSpO2();
                           ref.read(spo2MeasuringProvider.notifier).state = false;
                         } else {
                           RingPlugin.startSpO2();
                           ref.read(spo2MeasuringProvider.notifier).state = true;
                         }
                      },
                      icon: isMeasuring 
                          ? const SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.spo2)
                            )
                          : const Icon(Icons.play_circle_outline, size: 20),
                      label: Text(isMeasuring ? "Measuring..." : "Measure"),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.spo2,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TemperatureCard extends ConsumerWidget {
  final double value;
  final bool isDark;

  const _TemperatureCard({required this.value, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMeasuring = ref.watch(temperatureMeasuringProvider);
    final hasData = value > 0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: AppColors.temperature.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.temperature.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: isMeasuring
                ? SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.temperature,
                    ),
                  )
                : const Icon(
                    Icons.thermostat_rounded,
                    color: AppColors.temperature,
                    size: 32,
                  ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Skin Temperature',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      hasData ? value.toStringAsFixed(1) : '--',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: AppColors.temperature,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '°C',
                      style: TextStyle(
                        color: AppColors.temperature.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isMeasuring 
                          ? 'Measuring...' 
                          : (hasData ? _getTempCategory(value) : 'Not measured'),
                      style: TextStyle(
                        color: isMeasuring 
                            ? AppColors.temperature 
                            : (hasData ? AppColors.success : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: isMeasuring
                          ? null
                          : () {
                              ref.read(temperatureMeasuringProvider.notifier).state = true;
                              RingPlugin.startTemperature();
                            },
                      icon: isMeasuring
                          ? const SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.temperature)
                            )
                          : const Icon(Icons.play_circle_outline, size: 20),
                      label: Text(isMeasuring ? "Measuring..." : "Measure"),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.temperature,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTempCategory(double temp) {
    if (temp < 35.0) return 'Below normal';
    if (temp <= 37.2) return 'Normal range';
    if (temp <= 38.0) return 'Slightly elevated';
    return 'Elevated';
  }
}

class _BloodPressureCard extends ConsumerWidget {
  final int systolic;
  final int diastolic;
  final bool isDark;

  const _BloodPressureCard({
    required this.systolic,
    required this.diastolic,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMeasuring = ref.watch(bpMeasuringProvider);
    final progress = ref.watch(bpProgressValueProvider);
    final waveform = ref.watch(ppgWaveformProvider);
    final hasData = systolic > 0 && diastolic > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: AppColors.bloodPressure.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bloodPressure.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: isMeasuring
                    ? SizedBox(
                        width: 40,
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: progress > 0 ? progress / 100 : null,
                              strokeWidth: 3,
                              color: AppColors.bloodPressure,
                              backgroundColor: AppColors.bloodPressure.withValues(alpha: 0.1),
                            ),
                            Text(
                              '$progress%',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.bloodPressure,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const Icon(
                        Icons.speed_rounded,
                        color: AppColors.bloodPressure,
                        size: 28,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Blood Pressure',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          hasData ? '$systolic/$diastolic' : '--/--',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: AppColors.bloodPressure,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'mmHg',
                          style: TextStyle(
                            color: AppColors.bloodPressure.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // PPG Waveform
          if (isMeasuring && waveform.isNotEmpty) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 100,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  minY: waveform.reduce((a, b) => a < b ? a : b),
                  maxY: waveform.reduce((a, b) => a > b ? a : b),
                  lineBarsData: [
                    LineChartBarData(
                      spots: waveform
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      color: AppColors.bloodPressure,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.bloodPressure.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMeasuring
                    ? 'Acquiring PPG signal...'
                    : hasData
                        ? _getBPCategory(systolic, diastolic)
                        : 'PPG-based estimation',
                style: TextStyle(
                  color: hasData
                      ? AppColors.success
                      : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextButton.icon(
                onPressed: isMeasuring
                    ? () => RingPlugin.stopBloodPressure()
                    : () {
                          ref.read(bpMeasuringProvider.notifier).state = true;
                          ref.read(bpProgressValueProvider.notifier).state = 0;
                          ref.read(ppgWaveformProvider.notifier).state = [];
                          RingPlugin.startBloodPressure();
                        },
                icon: Icon(
                  isMeasuring ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                  size: 20,
                ),
                label: Text(isMeasuring ? 'Stop' : 'Measure'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.bloodPressure,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getBPCategory(int sys, int dia) {
    if (sys < 120 && dia < 80) return 'Normal';
    if (sys < 130 && dia < 80) return 'Elevated';
    if (sys < 140 || dia < 90) return 'High (Stage 1)';
    return 'High (Stage 2)';
  }
}
