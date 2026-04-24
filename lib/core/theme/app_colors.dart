import 'package:flutter/material.dart';

class AppColors {
  static const Color darkBase = Color(0xFF0A0A0F);
  static const Color green = Color(0xFF00A86B);
  static const Color gold = Color(0xFFC9A227);
  static const Color cyanHint = Color(0xFF00D4FF);

  static const Color primary = green;
  static const Color primaryLight = Color(0xFF2DCC90);
  static const Color primaryDark = Color(0xFF007E50);

  static const Color accent = gold;
  static const Color accentLight = Color(0xFFE0BF56);
  static const Color accentDark = Color(0xFF9C7A16);

  static const Color backgroundDark = darkBase;
  static const Color surfaceDark = Color(0xFF11141A);
  static const Color cardDark = Color(0xFF151A22);
  static const Color elevatedDark = Color(0xFF1C222C);
  static const Color cardBorderDark = Color(0xFF233041);

  static const Color backgroundLight = Color(0xFFF6F2E8);
  static const Color surfaceLight = Color(0xFFFFFCF7);
  static const Color cardLight = Color(0xFFFFFCF7);
  static const Color elevatedLight = Color(0xFFF2EBDD);
  static const Color cardBorderLight = Color(0xFFE7DDCB);

  static const Color textPrimaryDark = Color(0xFFF6F3EE);
  static const Color textSecondaryDark = Color(0xFF98A2B3);
  static const Color textMutedDark = Color(0xFF667085);

  static const Color textPrimaryLight = Color(0xFF171B20);
  static const Color textSecondaryLight = Color(0xFF5F6B7A);
  static const Color textMutedLight = Color(0xFF7A8593);

  static const Color heartRate = Color(0xFFE85D75);
  static const Color heartRateGlow = Color(0x40E85D75);
  static const Color spo2 = Color(0xFF32C5D2);
  static const Color spo2Low = Color(0xFFE6A23C);
  static const Color bloodPressure = gold;
  static const Color bloodGlucose = Color(0xFFEE7D52);
  static const Color ecg = cyanHint;
  static const Color temperature = Color(0xFFF39C5A);
  static const Color steps = Color(0xFF00A86B);
  static const Color sleep = Color(0xFF4E5CA8);
  static const Color hrv = Color(0xFF5AA37A);
  static const Color stress = Color(0xFFC66B37);
  static const Color calories = Color(0xFFD87C43);

  static const Color sleepDeep = Color(0xFF245C7A);
  static const Color sleepLight = Color(0xFF4B7AA3);
  static const Color sleepREM = Color(0xFF8361B5);
  static const Color sleepAwake = Color(0xFFC88A4B);

  static const Color success = green;
  static const Color warning = gold;
  static const Color error = Color(0xFFD95D5D);
  static const Color info = cyanHint;

  static const Color connected = green;
  static const Color connecting = gold;
  static const Color disconnected = Color(0xFF738091);

  static Gradient screenGradient(bool isDark) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [darkBase, Color(0xFF0D1117), Color(0xFF101723)]
          : const [Color(0xFFF8F4EC), Color(0xFFF5EFE4), Color(0xFFF2ECE0)],
    );
  }

  static BoxDecoration premiumPanelDecoration(bool isDark) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark ? [cardDark, elevatedDark] : [cardLight, elevatedLight],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: isDark ? cardBorderDark.withValues(alpha: 0.9) : cardBorderLight,
      ),
      boxShadow: [
        BoxShadow(
          color: (isDark ? Colors.black : darkBase).withValues(alpha: 0.18),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }
}
