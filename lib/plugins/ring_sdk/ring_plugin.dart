import 'dart:async';
import 'package:flutter/services.dart';
import 'models/scanned_device.dart';
import 'models/ring_connection_state.dart';

/// Flutter plugin bridge to the native NirvanaRing SDK.
///
/// Uses MethodChannel for commands and EventChannel for streams.
/// Android: wraps NirvanaRing .aar (com.lm.sdk.*)
/// iOS: wraps BCLRingSDK.xcframework
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
    _connectionStream ??= _connectionChannel.receiveBroadcastStream().map((event) {
      return RingConnectionState.fromString(event as String);
    }).asBroadcastStream();
    return _connectionStream!;
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

  static Future<void> getSteps() async {
    await _channel.invokeMethod('getSteps');
  }

  // ── Health Measurements ──

  static Future<void> startHeartRate() async {
    await _channel.invokeMethod('startHeartRate');
  }

  static Future<void> stopHeartRate() async {
    await _channel.invokeMethod('stopHeartRate');
  }

  static Future<void> startSpO2() async {
    await _channel.invokeMethod('startSpO2');
  }

  static Future<void> stopSpO2() async {
    await _channel.invokeMethod('stopSpO2');
  }

  static Future<void> startBloodPressure() async {
    await _channel.invokeMethod('startBloodPressure');
  }

  static Future<void> stopBloodPressure() async {
    await _channel.invokeMethod('stopBloodPressure');
  }

  static Future<void> startTemperature() async {
    await _channel.invokeMethod('startTemperature');
  }

  // ── Health Data Stream (single cached broadcast stream) ──

  static Stream<Map<String, dynamic>> get rawHealthData {
    _healthStream ??= _healthChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    }).asBroadcastStream();
    return _healthStream!;
  }

  // ── History ──

  static Future<void> readHistory() async {
    await _channel.invokeMethod('readHistory');
  }
}
