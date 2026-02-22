import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:synchronized/synchronized.dart';
import 'models/scanned_device.dart';
import 'models/ring_connection_state.dart';

/// Exception thrown when the ring is busy with another operation
class RingBusyException implements Exception {
  final String message;
  RingBusyException(this.message);
  @override
  String toString() => 'RingBusyException: $message';
}

/// Exception thrown when a feature is not supported by the connected ring
class RingFeatureNotSupportedException implements Exception {
  final String feature;
  RingFeatureNotSupportedException(this.feature);
  @override
  String toString() => 'RingFeatureNotSupportedException: $feature is not supported by this ring';
}

/// Flutter plugin bridge to the native ChipletRing SDK.
///
/// Uses MethodChannel for commands and EventChannel for streams.
/// Android: wraps ChipletRing .aar (com.lm.sdk.*)
/// iOS: wraps BCLRingSDK.xcframework
///
/// This implementation follows Yongxin SDK best practices:
/// - 3-second delay after connection before sending commands
/// - 300ms minimum spacing between consecutive commands
/// - No concurrent measurements allowed
/// - History sync blocks measurements
class RingPlugin {
  static const MethodChannel _channel = MethodChannel('com.seeknirvana.app/ring');
  static const EventChannel _scanChannel = EventChannel('com.seeknirvana.app/ring/scan');
  static const EventChannel _connectionChannel = EventChannel('com.seeknirvana.app/ring/connection');
  static const EventChannel _healthChannel = EventChannel('com.seeknirvana.app/ring/health');

  // Cached broadcast streams — EventChannel only supports ONE receiveBroadcastStream() call.
  // By caching the result, multiple listeners can safely subscribe.
  static Stream<List<ScannedDevice>>? _scanStream;
  static Stream<RingConnectionState>? _connectionStream;
  static Stream<Map<String, dynamic>>? _healthStream;

  // ── State Management ──
  
  static bool _isHistorySyncing = false;
  static bool _isMeasuring = false;
  static final _commandLock = Lock();
  static final _measurementStateController = StreamController<bool>.broadcast();
  static final _historySyncController = StreamController<bool>.broadcast();

  /// Stream that emits true when any measurement is in progress
  static Stream<bool> get measurementState => _measurementStateController.stream;
  
  /// Stream that emits true when history is syncing
  static Stream<bool> get historySyncState => _historySyncController.stream;

  /// Initialize the plugin and listen to health events for state tracking
  static void initialize() {
    rawHealthData.listen((data) {
      final type = data['type'] as String?;
      switch (type) {
        case 'historyStart':
          _isHistorySyncing = true;
          _historySyncController.add(true);
          break;
        case 'historyComplete':
        case 'historyError':
          _isHistorySyncing = false;
          _historySyncController.add(false);
          break;
        // Measurement COMPLETE/ERROR events - reset busy state
        case 'heartRateComplete':
        case 'heartRateError':
          if (_isMeasuring) {
            _isMeasuring = false;
            _measurementStateController.add(false);
          }
          break;
        case 'spo2Complete':
        case 'spo2Error':
          if (_isMeasuring) {
            _isMeasuring = false;
            _measurementStateController.add(false);
          }
          break;
        case 'bpError':
          if (_isMeasuring) {
            _isMeasuring = false;
            _measurementStateController.add(false);
          }
          break;
        case 'temperatureError':
          if (_isMeasuring) {
            _isMeasuring = false;
            _measurementStateController.add(false);
          }
          break;
      }
    });
  }

  /// Check if history sync is in progress
  static bool get isHistorySyncing => _isHistorySyncing;
  
  /// Check if any measurement is in progress
  static bool get isMeasuring => _isMeasuring;
  
  /// Check if ring is busy (syncing or measuring)
  static bool get isBusy => _isHistorySyncing || _isMeasuring;

  // ── Bluetooth State ──

  static Future<bool> isBluetoothEnabled() async {
    final result = await _channel.invokeMethod<bool>('isBluetoothEnabled');
    return result ?? false;
  }

  static Future<void> requestEnableBluetooth() async {
    await _channel.invokeMethod('requestEnableBluetooth');
  }

  static Future<String> requestBluetoothPermission() async {
    final result = await _channel.invokeMethod<String>('requestBluetoothPermission');
    return result ?? 'unknown';
  }

  // ── Scanning ──

  static Future<void> startScan() async {
    await _channel.invokeMethod('startScan');
  }

  static Future<void> stopScan() async {
    await _channel.invokeMethod('stopScan');
  }

  static Stream<List<ScannedDevice>> get scanResults {
    _scanStream ??= _scanChannel.receiveBroadcastStream().map((event) {
      final list = (event as List).cast<Map>();
      return list.map((e) => ScannedDevice.fromMap(Map<String, dynamic>.from(e))).toList();
    }).asBroadcastStream();
    return _scanStream!;
  }

  // ── Connection ──

  static Future<void> connect(String macAddress, {bool autoReconnect = false}) async {
    await _channel.invokeMethod('connect', {
      'mac': macAddress,
      'autoReconnect': autoReconnect,
    });
  }

  static Future<void> disconnect() async {
    _resetState();
    await _channel.invokeMethod('disconnect');
  }

  static Future<void> bind() async {
    await _channel.invokeMethod('bind');
  }

  static Future<void> unbind() async {
    await _channel.invokeMethod('unbind');
  }

  static Stream<RingConnectionState> get connectionState {
    _connectionStream ??= _connectionChannel.receiveBroadcastStream().map((event) {
      return RingConnectionState.fromString(event as String);
    }).asBroadcastStream();
    return _connectionStream!;
  }

  // ── RSSI ──

  static Future<void> startReadRSSI() async {
    await _channel.invokeMethod('startReadRSSI');
  }

  static Future<void> stopReadRSSI() async {
    await _channel.invokeMethod('stopReadRSSI');
  }

  // ── Device Info ──

  static Future<void> getBattery() async {
    await _channel.invokeMethod('getBattery');
  }

  static Future<void> getChargingState() async {
    await _channel.invokeMethod('getChargingState');
  }

  static Future<void> getSerialNumber() async {
    await _channel.invokeMethod('getSerialNumber');
  }

  static Future<void> getVersion() async {
    await _channel.invokeMethod('getVersion');
  }

  static Future<void> syncTime() async {
    await _channel.invokeMethod('syncTime');
  }

  static Future<void> getSteps() async {
    await _channel.invokeMethod('getSteps');
  }

  static Future<void> clearSteps() async {
    await _channel.invokeMethod('clearSteps');
  }

  // ── Health Measurements with Guards ──

  /// Throws [RingBusyException] if history is syncing or another measurement is in progress
  static Future<void> startHeartRate() async {
    await _assertCanStartMeasurement('Heart Rate');
    
    await _commandLock.synchronized(() async {
      try {
        await _channel.invokeMethod('startHeartRate');
        // Only set measuring state AFTER native call succeeds
        _isMeasuring = true;
        _measurementStateController.add(true);
      } catch (e) {
        _isMeasuring = false;
        _measurementStateController.add(false);
        rethrow;
      }
    });
  }

  static Future<void> stopHeartRate() async {
    await _channel.invokeMethod('stopHeartRate');
    _isMeasuring = false;
    _measurementStateController.add(false);
  }

  /// Throws [RingBusyException] if history is syncing or another measurement is in progress
  static Future<void> startSpO2() async {
    await _assertCanStartMeasurement('SpO2');
    
    await _commandLock.synchronized(() async {
      try {
        await _channel.invokeMethod('startSpO2');
        // Only set measuring state AFTER native call succeeds
        _isMeasuring = true;
        _measurementStateController.add(true);
      } catch (e) {
        _isMeasuring = false;
        _measurementStateController.add(false);
        rethrow;
      }
    });
  }

  static Future<void> stopSpO2() async {
    await _channel.invokeMethod('stopSpO2');
    _isMeasuring = false;
    _measurementStateController.add(false);
  }

  /// Throws [RingBusyException] if history is syncing or another measurement is in progress
  static Future<void> startBloodPressure() async {
    await _assertCanStartMeasurement('Blood Pressure');
    
    await _commandLock.synchronized(() async {
      try {
        await _channel.invokeMethod('startBloodPressure');
        // Only set measuring state AFTER native call succeeds
        _isMeasuring = true;
        _measurementStateController.add(true);
      } catch (e) {
        _isMeasuring = false;
        _measurementStateController.add(false);
        rethrow;
      }
    });
  }

  static Future<void> stopBloodPressure() async {
    await _channel.invokeMethod('stopBloodPressure');
    _isMeasuring = false;
    _measurementStateController.add(false);
  }

  /// Throws [RingBusyException] if history is syncing or another measurement is in progress
  static Future<void> startTemperature() async {
    await _assertCanStartMeasurement('Temperature');
    
    await _commandLock.synchronized(() async {
      try {
        await _channel.invokeMethod('startTemperature');
        // Only set measuring state AFTER native call succeeds
        _isMeasuring = true;
        _measurementStateController.add(true);
      } catch (e) {
        _isMeasuring = false;
        _measurementStateController.add(false);
        rethrow;
      }
    });
  }

  /// Asserts that a measurement can be started
  static Future<void> _assertCanStartMeasurement(String measurementType) async {
    if (_isHistorySyncing) {
      throw RingBusyException('Cannot start $measurementType measurement while history is syncing. Please wait for sync to complete.');
    }
    if (_isMeasuring) {
      throw RingBusyException('Cannot start $measurementType measurement while another measurement is in progress. Please stop the current measurement first.');
    }
  }

  // ── Health Data Stream (single cached broadcast stream) ──

  static Stream<Map<String, dynamic>> get rawHealthData {
    _healthStream ??= _healthChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    }).asBroadcastStream();
    return _healthStream!;
  }

  // ── History ──

  /// Note: History sync blocks measurements. Listen to [historySyncState] to check status.
  static Future<void> readHistory() async {
    await _channel.invokeMethod('readHistory');
  }

  static Future<void> deleteHistory() async {
    await _channel.invokeMethod('deleteHistory');
  }

  // ── Settings ──

  static Future<void> setBluetoothName(String name) async {
    await _channel.invokeMethod('setBluetoothName', {'name': name});
  }

  static Future<String?> getBluetoothName() async {
    final result = await _channel.invokeMethod<Map>('getBluetoothName');
    return result?['name'] as String?;
  }

  static Future<void> setPersonalInformation({
    int sex = 0,
    int age = 30,
    int height = 170,
    int weight = 70,
  }) async {
    await _channel.invokeMethod('setPersonalInformation', {
      'sex': sex,
      'age': age,
      'height': height,
      'weight': weight,
    });
  }

  static Future<Map<String, dynamic>?> getPersonalInformation() async {
    final result = await _channel.invokeMethod<Map>('getPersonalInformation');
    return result != null ? Map<String, dynamic>.from(result) : null;
  }

  static Future<void> restoreFactorySettings() async {
    await _channel.invokeMethod('restoreFactorySettings');
  }

  static Future<void> setCollectionPeriod(int period) async {
    await _channel.invokeMethod('setCollectionPeriod', {'period': period});
  }

  static Future<int?> getCollectionPeriod() async {
    final result = await _channel.invokeMethod<Map>('getCollectionPeriod');
    return result?['period'] as int?;
  }

  // ── PPG Settings ──

  static Future<void> setPPGFrequency({
    int hrFrequency = 0x30,
    int spo2Frequency = 0x30,
    int rawdataFrequency = 0x30,
  }) async {
    await _channel.invokeMethod('setPPGFrequency', {
      'hrFrequency': hrFrequency,
      'spo2Frequency': spo2Frequency,
      'rawdataFrequency': rawdataFrequency,
    });
  }

  static Future<void> setPPGStatus(int status) async {
    await _channel.invokeMethod('setPPGStatus', {'status': status});
  }

  static Future<int?> getPPGStatus() async {
    final result = await _channel.invokeMethod<Map>('getPPGStatus');
    return result?['status'] as int?;
  }

  // ── Sensor Settings ──

  static Future<void> setGyroscopeStatus(int status) async {
    await _channel.invokeMethod('setGyroscopeStatus', {'status': status});
  }

  static Future<int?> getGyroscopeStatus() async {
    final result = await _channel.invokeMethod<Map>('getGyroscopeStatus');
    return result?['status'] as int?;
  }

  static Future<void> setAccelerometerStatus(int status) async {
    await _channel.invokeMethod('setAccelerometerStatus', {'status': status});
  }

  static Future<int?> getAccelerometerStatus() async {
    final result = await _channel.invokeMethod<Map>('getAccelerometerStatus');
    return result?['status'] as int?;
  }

  static Future<void> setTemperatureStatus(int status) async {
    await _channel.invokeMethod('setTemperatureStatus', {'status': status});
  }

  static Future<int?> getTemperatureStatus() async {
    final result = await _channel.invokeMethod<Map>('getTemperatureStatus');
    return result?['status'] as int?;
  }

  static Future<void> setAutoCollectionStatus(int status) async {
    await _channel.invokeMethod('setAutoCollectionStatus', {'status': status});
  }

  static Future<int?> getAutoCollectionStatus() async {
    final result = await _channel.invokeMethod<Map>('getAutoCollectionStatus');
    return result?['status'] as int?;
  }

  // ── Advanced Features ──

  static Future<Map<String, dynamic>?> selfInspection() async {
    final result = await _channel.invokeMethod<Map>('selfInspection');
    return result != null ? Map<String, dynamic>.from(result) : null;
  }

  /// Set HID mode for gesture control
  /// 
  /// [touchMode] values:
  /// - 0x01: Control music
  /// - 0x02: Take photo
  /// - 0x04: Upload real-time audio
  /// - 0xFF: Close/Disable
  ///
  /// [gestureMode] values:
  /// - 0x01: Pinch to take photo
  /// - 0x02: Gesture video mode
  /// - 0xFF: Close/Disable
  static Future<void> setHIDMode({
    int touchMode = 0,
    int gestureMode = 0,
    int systemType = 0,
  }) async {
    await _channel.invokeMethod('setHIDMode', {
      'touchMode': touchMode,
      'gestureMode': gestureMode,
      'systemType': systemType,
    });
  }

  static Future<void> vibrate({int seconds = 1}) async {
    await _channel.invokeMethod('vibrate', {'seconds': seconds});
  }

  // ── Utility Methods ──

  /// Reset internal state (called on disconnect)
  static void _resetState() {
    _isHistorySyncing = false;
    _isMeasuring = false;
    _historySyncController.add(false);
    _measurementStateController.add(false);
  }

  /// Dispose resources
  static void dispose() {
    _measurementStateController.close();
    _historySyncController.close();
  }
}
