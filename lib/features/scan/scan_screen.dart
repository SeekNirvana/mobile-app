import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/ring_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';
import '../../plugins/ring_sdk/models/scanned_device.dart';
import '../../plugins/ring_sdk/models/ring_connection_state.dart';
import '../../services/ring_connection_service.dart';

/// Enum representing Bluetooth permission state
enum BluetoothPermissionState {
  checking,
  granted,
  denied,
  permanentlyDenied,
  bluetoothOff,
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  BluetoothPermissionState _permissionState = BluetoothPermissionState.checking;
  String? _permissionErrorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Check permissions and Bluetooth state on init
    if (ref.read(ringConnectionStateProvider) !=
        RingConnectionState.connected) {
      _checkPermissionsAndBluetooth();
    } else {
      setState(() => _permissionState = BluetoothPermissionState.granted);
    }
  }

  String _deviceTitle(ScannedDevice? device) {
    if (device == null) return 'Nirvana Ring';
    final trimmed = device.name.trim();
    return trimmed.isEmpty || trimmed.toLowerCase() == 'unknown'
        ? 'Nirvana Ring'
        : trimmed;
  }

  String _deviceShortId(ScannedDevice? device) {
    final mac = device?.macAddress ?? '';
    if (mac.isEmpty) return 'Ring nearby';
    final compact = mac.replaceAll(':', '');
    final suffix = compact.length >= 4
        ? compact.substring(compact.length - 4)
        : compact;
    return 'ID • ${suffix.toUpperCase()}';
  }

  String _signalLabel(ScannedDevice device) {
    if (device.rssi >= -55) return 'Excellent';
    if (device.rssi >= -67) return 'Strong';
    if (device.rssi >= -78) return 'Good';
    if (device.rssi >= -88) return 'Weak';
    return 'Far';
  }

  /// Check if Bluetooth is enabled
  Future<bool> _isBluetoothEnabled() async {
    try {
      final result = await const MethodChannel(
        'com.seeknirvana.app/ring',
      ).invokeMethod<bool>('isBluetoothEnabled');
      return result ?? false;
    } catch (e) {
      // If method doesn't exist, assume Bluetooth is on (backwards compatibility)
      return true;
    }
  }

  /// Request to enable Bluetooth
  Future<void> _requestEnableBluetooth() async {
    try {
      await const MethodChannel(
        'com.seeknirvana.app/ring',
      ).invokeMethod('requestEnableBluetooth');
    } catch (e) {
      // Method might not exist, show settings dialog instead
      if (mounted) {
        _showBluetoothSettingsDialog();
      }
    }
  }

  /// Request Bluetooth permission on iOS (triggers the permission dialog)
  Future<String> _requestBluetoothPermissionIOS() async {
    try {
      final result = await const MethodChannel(
        'com.seeknirvana.app/ring',
      ).invokeMethod<String>('requestBluetoothPermission');
      return result ?? 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }

  /// Check permissions and Bluetooth state
  Future<void> _checkPermissionsAndBluetooth() async {
    setState(() {
      _permissionState = BluetoothPermissionState.checking;
      _permissionErrorMessage = null;
    });

    // On iOS, use native CoreBluetooth permission check
    // permission_handler package doesn't properly map to CoreBluetooth on iOS
    if (Platform.isIOS) {
      final iosPermissionStatus = await _requestBluetoothPermissionIOS();
      if (iosPermissionStatus == 'denied' ||
          iosPermissionStatus == 'restricted') {
        setState(() {
          _permissionState = BluetoothPermissionState.permanentlyDenied;
          _permissionErrorMessage =
              'Bluetooth permission is denied. Please enable it in iOS Settings > Seek Nirvana.';
        });
        return;
      }

      // On iOS, if native permission is granted, check if Bluetooth is enabled
      final isBluetoothOn = await _isBluetoothEnabled();
      if (!isBluetoothOn) {
        setState(() {
          _permissionState = BluetoothPermissionState.bluetoothOff;
        });
        return;
      }

      // iOS permission granted and Bluetooth is on - proceed with scan
      setState(() => _permissionState = BluetoothPermissionState.granted);
      _startRealScan();
      return;
    }

    // First check if Bluetooth is enabled
    final isBluetoothOn = await _isBluetoothEnabled();
    if (!isBluetoothOn) {
      setState(() {
        _permissionState = BluetoothPermissionState.bluetoothOff;
      });
      return;
    }

    // Check and request BLE permissions (Android only)
    final permissionsToRequest = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];

    // Location permission is required for BLE scanning on Android < 12
    if (Platform.isAndroid) {
      permissionsToRequest.add(Permission.locationWhenInUse);
    }

    // Check current status before requesting
    final Map<Permission, PermissionStatus> currentStatuses = {};
    for (final permission in permissionsToRequest) {
      currentStatuses[permission] = await permission.status;
    }

    // Request permissions that are not granted
    final permissionsToRequestList = permissionsToRequest
        .where(
          (p) =>
              !currentStatuses[p]!.isGranted && !currentStatuses[p]!.isLimited,
        )
        .toList();

    Map<Permission, PermissionStatus> statuses = {};
    if (permissionsToRequestList.isNotEmpty) {
      statuses = await permissionsToRequestList.request();
    }

    // Merge with previously granted permissions
    for (final entry in currentStatuses.entries) {
      if (!statuses.containsKey(entry.key)) {
        statuses[entry.key] = entry.value;
      }
    }

    // Check if all required permissions are granted
    final allGranted = permissionsToRequest.every((p) {
      final status = statuses[p];
      return status != null && (status.isGranted || status.isLimited);
    });

    if (allGranted) {
      setState(() => _permissionState = BluetoothPermissionState.granted);
      _startRealScan();
    } else {
      // Check if any permission is permanently denied
      final anyPermanentlyDenied = statuses.values.any(
        (s) => s.isPermanentlyDenied,
      );
      if (anyPermanentlyDenied) {
        setState(() {
          _permissionState = BluetoothPermissionState.permanentlyDenied;
          _permissionErrorMessage =
              'Bluetooth permissions are permanently denied. Please enable them in app settings.';
        });
      } else {
        setState(() {
          _permissionState = BluetoothPermissionState.denied;
          _permissionErrorMessage =
              'Bluetooth permissions are required to scan for your ring.';
        });
      }
    }
  }

  /// Open app settings
  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  /// Show dialog to guide user to enable Bluetooth
  void _showBluetoothSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Required'),
        content: const Text(
          'Bluetooth is turned off. Please enable Bluetooth in your device settings to scan for your ring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _startRealScan() {
    if (ref.read(ringConnectionStateProvider) ==
        RingConnectionState.connected) {
      return;
    }

    ref.read(isScanningProvider.notifier).state = true;
    ref.read(ringConnectionStateProvider.notifier).state =
        RingConnectionState.scanning;
    ref.read(scannedDevicesProvider.notifier).state = [];

    // Listen to scan results from native
    RingPlugin.scanResults.listen((devices) {
      if (mounted) {
        ref.read(scannedDevicesProvider.notifier).state = devices;
      }
    });

    // Listen to connection state changes
    RingPlugin.connectionState.listen((state) {
      if (mounted) {
        ref.read(ringConnectionStateProvider.notifier).state = state;
        if (state == RingConnectionState.connected) {
          ref.read(isScanningProvider.notifier).state = false;
        }
      }
    });

    RingPlugin.startScan();

    // Auto-stop scan after 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && ref.read(isScanningProvider)) {
        _stopScan();
      }
    });
  }

  void _stopScan() {
    RingPlugin.stopScan();
    ref.read(isScanningProvider.notifier).state = false;
    if (ref.read(ringConnectionStateProvider) == RingConnectionState.scanning) {
      ref.read(ringConnectionStateProvider.notifier).state =
          RingConnectionState.disconnected;
    }
  }

  void _disconnect() {
    // Use explicit disconnect to clear saved device
    ref.read(ringConnectionServiceProvider).explicitDisconnect();
    ref.read(batteryLevelProvider.notifier).state = 0;
    ref.read(firmwareVersionProvider.notifier).state = '';
    _startRealScan();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    RingPlugin.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = ref.watch(isScanningProvider);
    final devices = ref.watch(scannedDevicesProvider);
    final connectionState = ref.watch(ringConnectionStateProvider);
    final connectedDevice = ref.watch(connectedDeviceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Your Ring'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (connectionState == RingConnectionState.connected)
            IconButton(
              icon: const Icon(Icons.link_off_rounded, color: Colors.redAccent),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            )
          else if (_permissionState == BluetoothPermissionState.granted &&
              !isScanning &&
              connectionState != RingConnectionState.connecting)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _checkPermissionsAndBluetooth,
            ),
        ],
      ),
      body: _buildBody(
        isScanning: isScanning,
        devices: devices,
        connectionState: connectionState,
        connectedDevice: connectedDevice,
        isDark: isDark,
      ),
    );
  }

  Widget _buildBody({
    required bool isScanning,
    required List<ScannedDevice> devices,
    required RingConnectionState connectionState,
    required ScannedDevice? connectedDevice,
    required bool isDark,
  }) {
    // Show permission/bluetooth state UI if not granted
    if (connectionState != RingConnectionState.connected) {
      switch (_permissionState) {
        case BluetoothPermissionState.checking:
          return _buildCheckingView();
        case BluetoothPermissionState.bluetoothOff:
          return _buildBluetoothOffView();
        case BluetoothPermissionState.denied:
          return _buildPermissionDeniedView(canRetry: true);
        case BluetoothPermissionState.permanentlyDenied:
          return _buildPermissionDeniedView(canRetry: false);
        case BluetoothPermissionState.granted:
          // Continue to normal view
          break;
      }
    }

    // Connected — show connected card only, no device list
    if (connectionState == RingConnectionState.connected) {
      return _buildConnectedView(connectedDevice, isDark);
    }

    return Column(
      children: [
        // Scan animation or idle/connecting state
        SizedBox(
          height: 200,
          child: Center(
            child: isScanning
                ? _buildScanningView()
                : connectionState == RingConnectionState.connecting
                ? _buildConnectingView()
                : _buildIdleView(devices),
          ),
        ),

        // Status message
        if (isScanning)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'Scanning for Nirvana Rings...\nMake sure your ring is powered on.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

        // Nearby rings list
        if (devices.isNotEmpty || !isScanning)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: [
                Text(
                  devices.isEmpty
                      ? 'No rings found'
                      : '${devices.length} ring${devices.length == 1 ? '' : 's'} nearby',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                const Spacer(),
                if (!isScanning &&
                    connectionState != RingConnectionState.connecting)
                  TextButton.icon(
                    onPressed: _checkPermissionsAndBluetooth,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Rescan'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // Device list
        Expanded(
          child: devices.isEmpty
              ? Center(
                  child: Text(
                    'Tap Rescan to search again.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: devices.length,
                  itemBuilder: (ctx, i) => _DeviceTile(
                    device: devices[i],
                    isDark: isDark,
                    isConnecting:
                        connectionState == RingConnectionState.connecting &&
                        ref.read(connectedDeviceProvider)?.macAddress ==
                            devices[i].macAddress,
                    onTap: () => _connectDevice(devices[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCheckingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Checking permissions...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothOffView() {
    // iOS cannot programmatically enable Bluetooth
    // Users must go to Control Center or Settings
    final isIOS = Platform.isIOS;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.bluetooth_disabled_rounded,
                color: Colors.orange,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Bluetooth is turned off',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isIOS
                  ? 'Please enable Bluetooth in Control Center or Settings to scan for your ring.'
                  : 'Please turn on Bluetooth to scan for your ring.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (isIOS)
              // iOS: Only show "Open Settings" and "Check Again" buttons
              Column(
                children: [
                  FilledButton.icon(
                    onPressed: _openAppSettings,
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Open Settings'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _checkPermissionsAndBluetooth,
                    child: const Text('Check again'),
                  ),
                ],
              )
            else
              // Android: Show "Turn on Bluetooth" button
              Column(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await _requestEnableBluetooth();
                      // Wait a moment for Bluetooth to turn on, then recheck
                      await Future.delayed(const Duration(seconds: 1));
                      if (mounted) {
                        _checkPermissionsAndBluetooth();
                      }
                    },
                    icon: const Icon(Icons.bluetooth_rounded),
                    label: const Text('Turn on Bluetooth'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _checkPermissionsAndBluetooth,
                    child: const Text('Check again'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView({required bool canRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.perm_device_information_rounded,
                color: Colors.redAccent,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Permissions Required',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _permissionErrorMessage ??
                  'Bluetooth permissions are required to scan for your ring.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (canRetry)
              FilledButton.icon(
                onPressed: _checkPermissionsAndBluetooth,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              )
            else
              FilledButton.icon(
                onPressed: _openAppSettings,
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Open Settings'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedView(ScannedDevice? connectedDevice, bool isDark) {
    final device = connectedDevice;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.green.withValues(alpha: 0.28),
                    AppColors.cyanHint.withValues(alpha: 0.14),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.connected,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Connected',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.connected,
              ),
            ),
            const SizedBox(height: 24),
            // Device info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.connected.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.connected.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.bluetooth_connected_rounded,
                          color: AppColors.connected,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _deviceTitle(device),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _deviceShortId(device),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      // Signal bars
                      if (device != null)
                        Row(
                          children: List.generate(
                            4,
                            (i) => Container(
                              width: 4,
                              height: 10 + i * 3.0,
                              margin: const EdgeInsets.only(left: 2),
                              decoration: BoxDecoration(
                                color: i < device.signalBars
                                    ? AppColors.connected
                                    : (isDark
                                        ? AppColors.cardBorderDark
                                        : AppColors.cardBorderLight),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (device != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _DeviceMiniChip(
                          icon: Icons.network_cell_rounded,
                          label:
                              '${_signalLabel(device)} · ${device.rssi} dBm',
                        ),
                        if (device.isBonded) ...[
                          const SizedBox(width: 8),
                          const _DeviceMiniChip(
                            icon: Icons.verified_rounded,
                            label: 'Paired',
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Disconnect button — prominent
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Disconnect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningView() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (ctx, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 0; i < 3; i++)
              Container(
                width: 80 + (i * 40) + (_pulseController.value * 40),
                height: 80 + (i * 40) + (_pulseController.value * 40),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3 - i * 0.08),
                    width: 2,
                  ),
                ),
              ),
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.bluetooth_searching_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConnectingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Connecting to ring...',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildIdleView(List<ScannedDevice> devices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.1),
          ),
          child: const Icon(
            Icons.bluetooth_rounded,
            color: AppColors.primary,
            size: 32,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          devices.isEmpty
              ? 'Tap refresh to scan'
              : '${devices.length} ring(s) found',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  void _connectDevice(ScannedDevice device) {
    _stopScan();
    ref.read(connectedDeviceProvider.notifier).state = device;
    ref.read(ringConnectionStateProvider.notifier).state =
        RingConnectionState.connecting;

    // Connect via native SDK
    RingPlugin.connect(device.macAddress);

    // Listen for connection state
    RingPlugin.connectionState.listen((state) {
      if (!mounted) return;

      if (state == RingConnectionState.connected) {
        ref.read(ringConnectionStateProvider.notifier).state =
            RingConnectionState.connected;

        // Only pop if this screen is currently visible to prevent black screen
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      } else if (state == RingConnectionState.disconnected) {
        ref.read(ringConnectionStateProvider.notifier).state =
            RingConnectionState.disconnected;
      }
    });
  }
}

class _DeviceTile extends StatelessWidget {
  final ScannedDevice device;
  final bool isDark;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isDark,
    required this.isConnecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final compactMac = device.macAddress.replaceAll(':', '');
    final suffix = compactMac.length >= 4
        ? compactMac.substring(compactMac.length - 4)
        : compactMac;
    final title =
        device.name.trim().isEmpty || device.name.toLowerCase() == 'unknown'
        ? 'Nirvana Ring'
        : device.name;
    final shortId = compactMac.isEmpty
        ? 'Ring nearby'
        : 'ID • ${suffix.toUpperCase()}';
    final signalLabel = device.rssi >= -55
        ? 'Excellent'
        : device.rssi >= -67
        ? 'Strong'
        : device.rssi >= -78
        ? 'Good'
        : device.rssi >= -88
        ? 'Weak'
        : 'Far';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isConnecting
                ? AppColors.primary
                : (isDark
                      ? AppColors.cardBorderDark
                      : AppColors.cardBorderLight),
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isConnecting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(
                      Icons.ring_volume_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(shortId, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DeviceMiniChip(
                        icon: Icons.network_cell_rounded,
                        label: '$signalLabel · ${device.rssi} dBm',
                      ),
                      if (device.isBonded)
                        const _DeviceMiniChip(
                          icon: Icons.verified_rounded,
                          label: 'Previously paired',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Pair button / signal bars
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: List.generate(
                    4,
                    (i) => Container(
                      width: 4,
                      height: 10 + i * 3.0,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: i < device.signalBars
                            ? AppColors.primary
                            : (isDark
                                  ? AppColors.cardBorderDark
                                  : AppColors.cardBorderLight),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: isConnecting ? null : onTap,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(isConnecting ? 'Pairing…' : 'Pair'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// _DeviceStatPill removed — no longer used in the redesigned scan screen.

class _DeviceMiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DeviceMiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
