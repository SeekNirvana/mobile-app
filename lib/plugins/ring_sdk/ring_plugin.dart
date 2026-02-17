import 'dart:async';
import 'package:flutter/services.dart';
import 'models/scanned_device.dart';
import 'models/ring_connection_state.dart';
import 'models/health_data_point.dart';

/// Flutter plugin bridge to the native ChipletRing SDK.
///
/// Uses MethodChannel for commands and EventChannel for streams.
/// Android: wraps ChipletRing.aar (com.lm.sdk.*)
/// iOS: wraps BCLRingSDK.xcframework
class RingPlugin {
  static const MethodChannel _channel = MethodChannel('com.seeknirvana.app/ring');
  static const EventChannel _scanChannel = EventChannel('com.seeknirvana.app/ring/scan');
  static const EventChannel _connectionChannel = EventChannel('com.seeknirvana.app/ring/connection');
  static const EventChannel _healthChannel = EventChannel('com.seeknirvana.app/ring/health');

  // ── Scanning ──

  static Future<void> startScan() async {
    await _channel.invokeMethod('startScan');
  }

  static Future<void> stopScan() async {
    await _channel.invokeMethod('stopScan');
  }

  static Stream<List<ScannedDevice>> get scanResults {
    return _scanChannel.receiveBroadcastStream().map((event) {
      final list = (event as List).cast<Map>();
      return list.map((e) => ScannedDevice.fromMap(Map<String, dynamic>.from(e))).toList();
    });
  }

  // ── Connection ──

  static Future<void> connect(String macAddress) async {
    await _channel.invokeMethod('connect', {'mac': macAddress});
  }

  static Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  static Future<void> bind() async {
    await _channel.invokeMethod('bind');
  }

  static Future<void> unbind() async {
    await _channel.invokeMethod('unbind');
  }

  static Stream<RingConnectionState> get connectionState {
    return _connectionChannel.receiveBroadcastStream().map((event) {
      return RingConnectionState.fromString(event as String);
    });
  }

  // ── Device Info ──

  static Future<void> getBattery() async {
    await _channel.invokeMethod('getBattery');
  }

  static Future<void> getVersion() async {
    await _channel.invokeMethod('getVersion');
  }

  static Future<void> syncTime() async {
    await _channel.invokeMethod('syncTime');
  }

  static Future<int> getSteps() async {
    final result = await _channel.invokeMethod<int>('getSteps');
    return result ?? 0;
  }

  // ── Health Measurements ──

  static Future<void> startHeartRate() async {
    await _channel.invokeMethod('startHeartRate');
  }

  static Future<void> stopHeartRate() async {
    await _channel.invokeMethod('stopHeartRate');
  }

  static Future<void> startBloodOxygen() async {
    await _channel.invokeMethod('startBloodOxygen');
  }

  static Future<void> stopBloodOxygen() async {
    await _channel.invokeMethod('stopBloodOxygen');
  }

  static Future<void> startBloodPressure() async {
    await _channel.invokeMethod('startBloodPressure');
  }

  static Future<void> stopBloodPressure() async {
    await _channel.invokeMethod('stopBloodPressure');
  }

  static Future<void> startECG() async {
    await _channel.invokeMethod('startECG');
  }

  static Future<void> stopECG() async {
    await _channel.invokeMethod('stopECG');
  }

  static Future<void> startTemperature() async {
    await _channel.invokeMethod('startTemperature');
  }

  static Future<void> startBloodGlucose() async {
    await _channel.invokeMethod('startBloodGlucose');
  }

  static Future<void> stopBloodGlucose() async {
    await _channel.invokeMethod('stopBloodGlucose');
  }

  // ── Health Data Stream ──

  static Stream<HealthDataPoint> get healthData {
    return _healthChannel.receiveBroadcastStream().map((event) {
      return HealthDataPoint.fromMap(Map<String, dynamic>.from(event as Map));
    });
  }

  /// Raw health data stream for direct map access (battery, version, etc.)
  static Stream<Map<String, dynamic>> get rawHealthData {
    return _healthChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }

  // ── Sleep Data ──

  static Future<Map<String, dynamic>?> getSleepData() async {
    final result = await _channel.invokeMethod<Map>('getSleepData');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  // ── Firmware ──

  static Future<void> startOTA(String filePath) async {
    await _channel.invokeMethod('startOTA', {'filePath': filePath});
  }

  // ── History ──

  static Future<void> readHistory() async {
    await _channel.invokeMethod('readHistory');
  }

  static Future<void> startSpO2() async {
    await _channel.invokeMethod('startSpO2');
  }

  static Future<void> stopSpO2() async {
    await _channel.invokeMethod('stopSpO2');
  }
}

