import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../plugins/ring_sdk/ring_plugin.dart';
import '../plugins/ring_sdk/models/ring_connection_state.dart';
import '../plugins/ring_sdk/models/scanned_device.dart';
import '../providers/ring_provider.dart';

/// Service that manages ring connection persistence and auto-reconnection.
/// Saves MAC address when connected, clears on explicit disconnect,
/// and auto-reconnects on app startup if a device was previously connected.
class RingConnectionService {
  final Ref ref;
  StreamSubscription? _connectionSub;
  bool _isExplicitDisconnect = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;

  RingConnectionService(this.ref) {
    _init();
  }

  void _init() {
    // Listen to connection state changes
    _connectionSub = RingPlugin.connectionState.listen((state) {
      _handleConnectionStateChange(state);
    });

    // Attempt auto-reconnect on startup
    if (Platform.isIOS) {
      debugPrint(
        '[RingConnectionService] Skipping auto-reconnect on iOS startup.',
      );
      return;
    }
    _attemptAutoReconnect();
  }

  void _handleConnectionStateChange(RingConnectionState state) {
    final currentState = ref.read(ringConnectionStateProvider);

    // Update the provider
    ref.read(ringConnectionStateProvider.notifier).state = state;

    switch (state) {
      case RingConnectionState.connected:
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        // Save the MAC address when successfully connected
        _saveCurrentDevice();
        break;
      case RingConnectionState.disconnected:
        if (_isExplicitDisconnect) {
          // User explicitly disconnected - clear saved device
          clearSavedDevice();
          _isExplicitDisconnect = false;
        } else if (currentState == RingConnectionState.connected) {
          // Unexpected disconnect - attempt reconnect
          _scheduleReconnect();
        }
        break;
      case RingConnectionState.connecting:
        // Connection in progress
        break;
      case RingConnectionState.scanning:
        // Scanning for devices
        break;
      case RingConnectionState.bound:
        // Device bound but not yet connected
        break;
      case RingConnectionState.disconnecting:
        // Disconnecting in progress
        break;
    }
  }

  Future<void> _attemptAutoReconnect() async {
    final savedMac = await getSavedMacAddress();
    final savedName = await getSavedDeviceName();

    if (savedMac != null && savedMac.isNotEmpty) {
      debugPrint(
        '[RingConnectionService] Auto-reconnecting to $savedName ($savedMac)',
      );
      ref.read(autoReconnectingProvider.notifier).state = true;

      // Set state to connecting
      ref.read(ringConnectionStateProvider.notifier).state =
          RingConnectionState.connecting;

      // Attempt connection
      try {
        await RingPlugin.connect(savedMac);

        // Restore the connected device info
        ref.read(connectedDeviceProvider.notifier).state = ScannedDevice(
          name: savedName ?? 'Loop Ring',
          macAddress: savedMac,
          rssi: -50, // Default RSSI since we don't have the actual value
          isBonded: true,
        );
      } catch (e) {
        debugPrint('[RingConnectionService] Auto-reconnect failed: $e');
        _scheduleReconnect();
      }

      ref.read(autoReconnectingProvider.notifier).state = false;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[RingConnectionService] Max reconnect attempts reached');
      return;
    }

    _reconnectAttempts++;
    debugPrint(
      '[RingConnectionService] Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: 2 * _reconnectAttempts), () {
      _attemptAutoReconnect();
    });
  }

  Future<void> _saveCurrentDevice() async {
    final device = ref.read(connectedDeviceProvider);
    if (device != null) {
      await saveConnectedDevice(device.macAddress, device.name);
      debugPrint(
        '[RingConnectionService] Saved device: ${device.name} (${device.macAddress})',
      );
    }
  }

  /// Call this when user explicitly disconnects
  Future<void> explicitDisconnect() async {
    _isExplicitDisconnect = true;
    _reconnectTimer?.cancel();
    await RingPlugin.disconnect();
    await clearSavedDevice();
    ref.read(connectedDeviceProvider.notifier).state = null;
  }

  void dispose() {
    _connectionSub?.cancel();
    _reconnectTimer?.cancel();
  }
}

/// Provider for the ring connection service
final ringConnectionServiceProvider = Provider<RingConnectionService>((ref) {
  return RingConnectionService(ref);
});
