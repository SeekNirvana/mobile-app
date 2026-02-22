import 'package:flutter/foundation.dart';

/// Exception thrown when attempting to use a feature not supported by the ring
class FeatureNotSupportedException implements Exception {
  final String feature;
  final String message;
  
  FeatureNotSupportedException(this.feature, [this.message = '']);
  
  @override
  String toString() => 'FeatureNotSupportedException: $feature is not supported${message.isNotEmpty ? ' - $message' : ''}';
}

/// Service to detect and manage ring capabilities.
/// Uses capability flags sent from native SDK during connection.
/// 
/// This is a singleton service that maintains the state of ring capabilities
/// throughout the app lifecycle.
class FeatureDetectionService {
  static final Map<String, bool> _capabilities = {};
  static final Map<String, dynamic> _deviceInfo = {};
  static final List<void Function()> _listeners = [];
  
  /// Add a listener to be notified when capabilities change
  static void addListener(void Function() listener) {
    _listeners.add(listener);
  }
  
  /// Remove a listener
  static void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
  
  /// Notify all listeners of capability changes
  static void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('[FeatureDetection] Error notifying listener: $e');
      }
    }
  }
  
  /// Platform-specific capabilities (set manually for features not in SDK)
  static void setPlatformCapabilities({
    bool ppgBloodPressure = false,
  }) {
    _capabilities['ppgBloodPressureSupported'] = ppgBloodPressure;
    _notifyListeners();
  }
  
  /// Update capabilities from native SDK (called from RingDataService)
  static void updateCapabilities(Map<String, dynamic> flags) {
    _capabilities.clear();
    _capabilities.addAll({
      // HID Features
      'hidSupported': flags['isHIDSupported'] ?? false,
      'hidTouchPhotoSupported': flags['isTouchPhotoSupported'] ?? false,
      'hidTouchVideoSupported': flags['isTouchShortVideoSupported'] ?? false,
      'hidTouchMusicSupported': flags['isTouchMusicControlSupported'] ?? false,
      'hidTouchPPTSupported': flags['isTouchPPTControlSupported'] ?? false,
      'hidPinchPhotoSupported': flags['isPinchPhotoSupported'] ?? false,
      'hidGestureVideoSupported': flags['isGestureShortVideoSupported'] ?? false,
      'hidGestureMusicSupported': flags['isGestureMusicControlSupported'] ?? false,
      'hidGesturePPTSupported': flags['isGesturePPTControlSupported'] ?? false,
      'hidSnapPhotoSupported': flags['isSnapPhotoSupported'] ?? false,
      
      // Health Features
      'bloodPressureSupported': flags['isBloodPressureMeasurementSupported'] ?? false,
      'bloodGlucoseSupported': flags['isBloodGlucoseMeasurementSupported'] ?? false,
      'ecgSupported': flags['isEcgFunctionSupported'] ?? false,
      
      // Hardware Features
      'vibrationSupported': flags['isVibrationAlarmSupported'] ?? false,
      'voiceRecordingSupported': flags['isMicrophoneSupported'] ?? false,
      'fileSystemSupported': flags['isFileSystemSupported'] ?? false,
      'sportModeSupported': flags['isSportModeSupported'] ?? false,
      'goMoreSleepSupported': flags['isGoMoreSleepAlgorithmSupported'] ?? false,
      
      // Curve/Graph Features
      'heartRateCurveSupported': flags['isHeartRateCurveSupported'] ?? false,
      'oxygenCurveSupported': flags['isOxygenCurveSupported'] ?? false,
      'variabilityCurveSupported': flags['isVariabilityCurveSupported'] ?? false,
      'pressureCurveSupported': flags['isPressureCurveSupported'] ?? false,
      'temperatureCurveSupported': flags['isTemperatureCurveSupported'] ?? false,
      
      // Other Features
      'femaleHealthSupported': flags['isFemaleHealthSupported'] ?? false,
    });
    
    _deviceInfo['firmwareVersion'] = flags['firmwareVersion'];
    _deviceInfo['hardwareVersion'] = flags['hardwareVersion'];
    _deviceInfo['batteryLevel'] = flags['batteryLevel'];
    _deviceInfo['stepCount'] = flags['stepCount'];
    _deviceInfo['collectInterval'] = flags['collectInterval'];
    _deviceInfo['chargingState'] = flags['chargingState'];
    
    debugPrint('[FeatureDetection] Capabilities updated:');
    _capabilities.forEach((key, value) {
      if (value) debugPrint('  ✓ $key');
    });
    
    _notifyListeners();
  }
  
  // MARK: - HID Features
  
  static bool get supportsHID => _capabilities['hidSupported'] ?? false;
  static bool get supportsTouchPhoto => _capabilities['hidTouchPhotoSupported'] ?? false;
  static bool get supportsTouchVideo => _capabilities['hidTouchVideoSupported'] ?? false;
  static bool get supportsTouchMusic => _capabilities['hidTouchMusicSupported'] ?? false;
  static bool get supportsTouchPPT => _capabilities['hidTouchPPTSupported'] ?? false;
  static bool get supportsPinchPhoto => _capabilities['hidPinchPhotoSupported'] ?? false;
  static bool get supportsGestureVideo => _capabilities['hidGestureVideoSupported'] ?? false;
  static bool get supportsGestureMusic => _capabilities['hidGestureMusicSupported'] ?? false;
  static bool get supportsGesturePPT => _capabilities['hidGesturePPTSupported'] ?? false;
  static bool get supportsSnapPhoto => _capabilities['hidSnapPhotoSupported'] ?? false;
  
  /// Returns true if any HID feature is supported
  static bool get supportsAnyHID => supportsHID && (
    supportsTouchPhoto || 
    supportsTouchVideo || 
    supportsTouchMusic || 
    supportsTouchPPT || 
    supportsPinchPhoto || 
    supportsGestureVideo || 
    supportsGestureMusic || 
    supportsGesturePPT || 
    supportsSnapPhoto
  );
  
  /// Get list of supported HID touch features
  static List<String> get supportedTouchFeatures {
    final features = <String>[];
    if (supportsTouchPhoto) features.add('Photo');
    if (supportsTouchVideo) features.add('Video');
    if (supportsTouchMusic) features.add('Music');
    if (supportsTouchPPT) features.add('PPT');
    return features;
  }
  
  /// Get list of supported HID gesture features
  static List<String> get supportedGestureFeatures {
    final features = <String>[];
    if (supportsPinchPhoto) features.add('Pinch Photo');
    if (supportsGestureVideo) features.add('Gesture Video');
    if (supportsGestureMusic) features.add('Gesture Music');
    if (supportsGesturePPT) features.add('Gesture PPT');
    if (supportsSnapPhoto) features.add('Snap Photo');
    return features;
  }
  
  // MARK: - Health Features
  
  static bool get supportsBloodPressure => 
    (_capabilities['bloodPressureSupported'] ?? false) || 
    (_capabilities['ppgBloodPressureSupported'] ?? false);
  
  static bool get supportsNativeBloodPressure => _capabilities['bloodPressureSupported'] ?? false;
  static bool get supportsPPGBloodPressure => _capabilities['ppgBloodPressureSupported'] ?? false;
  static bool get supportsBloodGlucose => _capabilities['bloodGlucoseSupported'] ?? false;
  static bool get supportsECG => _capabilities['ecgSupported'] ?? false;
  static bool get supportsVibration => _capabilities['vibrationSupported'] ?? false;
  static bool get supportsVoiceRecording => _capabilities['voiceRecordingSupported'] ?? false;
  static bool get supportsGoMoreSleep => _capabilities['goMoreSleepSupported'] ?? false;
  static bool get supportsFemaleHealth => _capabilities['femaleHealthSupported'] ?? false;
  
  // MARK: - Hardware Features
  
  static bool get supportsFileSystem => _capabilities['fileSystemSupported'] ?? false;
  static bool get supportsSportMode => _capabilities['sportModeSupported'] ?? false;
  
  // MARK: - Curve/Graph Features
  
  static bool get supportsHeartRateCurve => _capabilities['heartRateCurveSupported'] ?? false;
  static bool get supportsOxygenCurve => _capabilities['oxygenCurveSupported'] ?? false;
  static bool get supportsVariabilityCurve => _capabilities['variabilityCurveSupported'] ?? false;
  static bool get supportsPressureCurve => _capabilities['pressureCurveSupported'] ?? false;
  static bool get supportsTemperatureCurve => _capabilities['temperatureCurveSupported'] ?? false;
  
  /// Returns true if any curve/graph feature is supported
  static bool get supportsAnyCurve => 
    supportsHeartRateCurve || 
    supportsOxygenCurve || 
    supportsVariabilityCurve || 
    supportsPressureCurve || 
    supportsTemperatureCurve;
  
  // MARK: - Device Info
  
  static String? get firmwareVersion => _deviceInfo['firmwareVersion'] as String?;
  static String? get hardwareVersion => _deviceInfo['hardwareVersion'] as String?;
  static int? get batteryLevel => _deviceInfo['batteryLevel'] as int?;
  static int? get stepCount => _deviceInfo['stepCount'] as int?;
  static int? get collectInterval => _deviceInfo['collectInterval'] as int?;
  static bool? get isCharging => _deviceInfo['chargingState'] as bool?;
  
  // MARK: - Extended Features Summary
  
  /// Check if any extended features are supported
  static bool get hasExtendedFeatures => 
    supportsHID || 
    supportsBloodPressure || 
    supportsBloodGlucose || 
    supportsECG || 
    supportsVibration ||
    supportsVoiceRecording ||
    supportsSportMode ||
    supportsGoMoreSleep;
  
  /// Get a summary of all supported features
  static Map<String, List<String>> get supportedFeaturesSummary {
    final summary = <String, List<String>>{};
    
    if (supportsAnyHID) {
      summary['HID Gestures'] = [
        ...supportedTouchFeatures,
        ...supportedGestureFeatures,
      ];
    }
    
    final healthFeatures = <String>[];
    if (supportsBloodPressure) healthFeatures.add('Blood Pressure');
    if (supportsBloodGlucose) healthFeatures.add('Blood Glucose');
    if (supportsECG) healthFeatures.add('ECG');
    if (supportsVibration) healthFeatures.add('Vibration/Alarms');
    if (supportsFemaleHealth) healthFeatures.add('Female Health');
    if (healthFeatures.isNotEmpty) {
      summary['Health'] = healthFeatures;
    }
    
    final otherFeatures = <String>[];
    if (supportsVoiceRecording) otherFeatures.add('Voice Recording');
    if (supportsFileSystem) otherFeatures.add('File System');
    if (supportsSportMode) otherFeatures.add('Sport Mode');
    if (supportsGoMoreSleep) otherFeatures.add('GoMore Sleep');
    if (otherFeatures.isNotEmpty) {
      summary['Other'] = otherFeatures;
    }
    
    return summary;
  }
  
  // MARK: - Utility Methods
  
  /// Assert that a feature is supported, throw exception if not
  static void assertSupported(String feature, bool isSupported) {
    if (!isSupported) {
      throw FeatureNotSupportedException(feature);
    }
  }
  
  /// Get capability value by name
  static bool getCapability(String name) {
    return _capabilities[name] ?? false;
  }
  
  /// Get all capabilities as a map
  static Map<String, bool> get allCapabilities => Map.unmodifiable(_capabilities);
  
  /// Get all device info as a map
  static Map<String, dynamic> get allDeviceInfo => Map.unmodifiable(_deviceInfo);
  
  /// Reset capabilities (on disconnect)
  static void reset() {
    debugPrint('[FeatureDetection] Resetting capabilities');
    _capabilities.clear();
    _deviceInfo.clear();
    _notifyListeners();
  }
  
  /// Check if capabilities have been loaded
  static bool get hasCapabilities => _capabilities.isNotEmpty;
}
