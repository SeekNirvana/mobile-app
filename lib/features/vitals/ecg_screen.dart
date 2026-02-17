import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class ECGScreen extends StatefulWidget {
  const ECGScreen({super.key});

  @override
  State<ECGScreen> createState() => _ECGScreenState();
}

class _ECGScreenState extends State<ECGScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _ecgData = [];
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    );
    // Generate mock ECG waveform
    _generateMockECG();
  }

  void _generateMockECG() {
    final random = Random();
    for (int i = 0; i < 300; i++) {
      final t = i / 300.0;
      final cycle = (t * 6 * pi);
      // Simulate PQRST waveform
      double value = 0;
      final phase = cycle % (2 * pi);
      if (phase < 0.3) {
        value = 0.1 * sin(phase * 10); // P wave
      } else if (phase < 0.5) {
        value = -0.15; // Q
      } else if (phase < 0.7) {
        value = 0.8 * sin((phase - 0.5) * pi / 0.2); // R peak
      } else if (phase < 0.9) {
        value = -0.2; // S
      } else if (phase < 1.5) {
        value = 0.15 * sin((phase - 0.9) * pi / 0.6); // T wave
      } else {
        value = 0.0 + random.nextDouble() * 0.02 - 0.01; // Baseline
      }
      _ecgData.add(value + random.nextDouble() * 0.03 - 0.015);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ECG Recording'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ECG Waveform
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : Colors.white,
                borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                border: Border.all(
                  color: AppColors.ecg.withValues(alpha: 0.3),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                child: CustomPaint(
                  painter: _ECGPainter(
                    data: _ecgData,
                    color: AppColors.ecg,
                    gridColor: isDark
                        ? AppColors.cardBorderDark
                        : AppColors.cardBorderLight,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Stats
            Row(
              children: [
                _StatChip(label: 'HR', value: '72 BPM', color: AppColors.heartRate),
                const SizedBox(width: 12),
                _StatChip(label: 'PR', value: '164 ms', color: AppColors.spo2),
                const SizedBox(width: 12),
                _StatChip(label: 'QRS', value: '88 ms', color: AppColors.primary),
              ],
            ),

            const SizedBox(height: 24),

            // Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.info, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Place your finger firmly on the ring sensor for 30 seconds during recording.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Record Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() => _isRecording = !_isRecording);
                },
                icon: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  _isRecording ? 'Stop Recording' : 'Start ECG Recording',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? AppColors.error : AppColors.ecg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ECGPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final Color gridColor;

  _ECGPainter({
    required this.data,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    const gridSpacing = 25.0;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (data.isEmpty) return;

    // Draw ECG line
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final mid = size.height / 2;
    final xStep = size.width / (data.length - 1);

    path.moveTo(0, mid - data[0] * mid * 0.8);
    for (int i = 1; i < data.length; i++) {
      path.lineTo(i * xStep, mid - data[i] * mid * 0.8);
    }

    canvas.drawPath(path, paint);

    // Draw glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
