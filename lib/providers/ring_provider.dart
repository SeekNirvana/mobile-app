import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../plugins/ring_sdk/models/ring_connection_state.dart';
import '../plugins/ring_sdk/models/scanned_device.dart';

// Key for storing MAC address in SharedPreferences
const String _macAddressKey = 'saved_ring_mac_address';
const String _deviceNameKey = 'saved_ring_device_name';

/// Save the connected device's MAC address to persistent storage
Future<void> saveConnectedDevice(String macAddress, String deviceName) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_macAddressKey, macAddress);
  await prefs.setString(_deviceNameKey, deviceName);
}

/// Get the saved MAC address from persistent storage
Future<String?> getSavedMacAddress() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_macAddressKey);
}

/// Get the saved device name from persistent storage
Future<String?> getSavedDeviceName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_deviceNameKey);
}

/// Clear the saved device (called on explicit disconnect)
Future<void> clearSavedDevice() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_macAddressKey);
  await prefs.remove(_deviceNameKey);
}

/// Provider for the saved MAC address
final savedMacAddressProvider = FutureProvider<String?>((ref) async {
  return await getSavedMacAddress();
});

/// Provider to track if auto-reconnect is in progress
final autoReconnectingProvider = StateProvider<bool>((ref) => false);

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

final serialNumberProvider = StateProvider<String>((ref) {
  return '';
});

final rssiProvider = StateProvider<int>((ref) {
  return 0;
});

final heartRateMeasuringProvider = StateProvider<bool>((ref) => false);
final spo2MeasuringProvider = StateProvider<bool>((ref) => false);

final historyDataProvider = StateProvider<List<Map<String, dynamic>>>((ref) {
  return [];
});
