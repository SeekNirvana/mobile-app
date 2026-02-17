import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../plugins/ring_sdk/models/ring_connection_state.dart';
import '../plugins/ring_sdk/models/scanned_device.dart';

/// Mock ring provider for UI development.
/// In production, this will be backed by RingPlugin streams.
final ringConnectionStateProvider = StateProvider<RingConnectionState>((ref) {
  return RingConnectionState.disconnected;
});

final scannedDevicesProvider = StateProvider<List<ScannedDevice>>((ref) {
  return [];
});

final connectedDeviceProvider = StateProvider<ScannedDevice?>((ref) {
  return null;
});

final isScanningProvider = StateProvider<bool>((ref) {
  return false;
});

final batteryLevelProvider = StateProvider<int>((ref) {
  return 0;
});

final firmwareVersionProvider = StateProvider<String>((ref) {
  return '';
});

final heartRateMeasuringProvider = StateProvider<bool>((ref) => false);
final spo2MeasuringProvider = StateProvider<bool>((ref) => false);

final historyDataProvider = StateProvider<List<Map<String, dynamic>>>((ref) {
  return [];
});
