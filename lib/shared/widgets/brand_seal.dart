import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class BrandSeal extends StatelessWidget {
  final double size;
  final bool isDark;
  final double padding;
  final bool showHalo;

  const BrandSeal({
    super.key,
    required this.size,
    required this.isDark,
    this.padding = 0,
    this.showHalo = true,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = isDark ? AppColors.backgroundDark : Colors.white;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.18, -0.22),
          radius: 0.95,
          colors: [
            baseColor,
            Color.lerp(baseColor, AppColors.gold, isDark ? 0.08 : 0.05)!,
          ],
        ),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: isDark ? 0.42 : 0.26),
          width: 1.2,
        ),
        boxShadow: showHalo
            ? [
                BoxShadow(
                  color: AppColors.green.withValues(alpha: 0.16),
                  blurRadius: size * 0.34,
                  offset: Offset(0, size * 0.12),
                ),
                BoxShadow(
                  color: AppColors.cyanHint.withValues(alpha: 0.08),
                  blurRadius: size * 0.20,
                  offset: const Offset(0, 0),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF05070A) : const Color(0xFFF7F8F4),
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.04),
            child: Image.asset(
              'assets/branding/seeknirvana_mark.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
