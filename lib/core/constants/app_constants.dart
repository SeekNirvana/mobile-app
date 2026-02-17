class AppConstants {
  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingSM = 8.0;
  static const double spacingMD = 16.0;
  static const double spacingLG = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // Border radius
  static const double radiusSM = 8.0;
  static const double radiusMD = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 20.0;
  static const double radiusXXL = 28.0;
  static const double radiusFull = 100.0;

  // Card sizes
  static const double cardHeight = 160.0;
  static const double cardHeightSmall = 120.0;

  // Animation durations
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animNormal = Duration(milliseconds: 350);
  static const Duration animSlow = Duration(milliseconds: 600);
  static const Duration animPulse = Duration(milliseconds: 1200);

  // Health reference ranges
  static const int hrMin = 40;
  static const int hrMax = 200;
  static const int hrRestingMin = 60;
  static const int hrRestingMax = 100;

  static const int spo2Normal = 95;
  static const int spo2Low = 90;

  static const double tempNormalMin = 36.1;
  static const double tempNormalMax = 37.2;

  static const int defaultStepGoal = 10000;

  // BLE
  static const Duration scanTimeout = Duration(seconds: 10);
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const int maxReconnectAttempts = 5;
}
