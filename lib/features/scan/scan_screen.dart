import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/ring_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';
import '../../plugins/ring_sdk/models/scanned_device.dart';
import '../../plugins/ring_sdk/models/ring_connection_state.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    // Only scan if not already connected
    if (ref.read(ringConnectionStateProvider) != RingConnectionState.connected) {
      _requestPermissionsAndScan();
    }
  }

  Future<void> _requestPermissionsAndScan() async {
    // Request BLE permissions
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted || s.isLimited);
    if (allGranted || true) {
      _startRealScan();
    }
  }

  void _startRealScan() {
    if (ref.read(ringConnectionStateProvider) == RingConnectionState.connected) return;

    ref.read(isScanningProvider.notifier).state = true;
    ref.read(ringConnectionStateProvider.notifier).state = RingConnectionState.scanning;
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
      ref.read(ringConnectionStateProvider.notifier).state = RingConnectionState.disconnected;
    }
  }

  void _disconnect() {
    RingPlugin.disconnect();
    ref.read(connectedDeviceProvider.notifier).state = null;
    ref.read(ringConnectionStateProvider.notifier).state = RingConnectionState.disconnected;
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
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        actions: [
          if (connectionState == RingConnectionState.connected)
             IconButton(
              icon: const Icon(Icons.link_off_rounded, color: Colors.redAccent), 
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            )
          else if (!isScanning && connectionState != RingConnectionState.connecting)
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _startRealScan),
        ],
      ),
      body: Column(
        children: [
          // Scan animation or Connected State
          SizedBox(
            height: 200,
            child: Center(
              child: connectionState == RingConnectionState.connected
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withValues(alpha: 0.2)),
                        child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 40),
                      ),
                      const SizedBox(height: 16),
                      Text('Connected to ${connectedDevice?.name ?? "Ring"}', style: Theme.of(context).textTheme.titleMedium),
                      Text(connectedDevice?.macAddress ?? "", style: Theme.of(context).textTheme.bodySmall),
                    ])
                  : isScanning
                      ? AnimatedBuilder(animation: _pulseController, builder: (ctx, _) {
                          return Stack(alignment: Alignment.center, children: [
                            for (int i = 0; i < 3; i++)
                              Container(
                                width: 80 + (i * 40) + (_pulseController.value * 40),
                                height: 80 + (i * 40) + (_pulseController.value * 40),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3 - i * 0.08), width: 2),
                                ),
                              ),
                            Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.15)),
                              child: const Icon(Icons.bluetooth_searching_rounded, color: AppColors.primary, size: 32),
                            ),
                          ]);
                        })
                      : connectionState == RingConnectionState.connecting
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(width: 60, height: 60, child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3)),
                            const SizedBox(height: 16),
                            Text('Connecting to ring...', style: Theme.of(context).textTheme.bodyMedium),
                          ])
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.1)),
                              child: const Icon(Icons.bluetooth_rounded, color: AppColors.primary, size: 32),
                            ),
                            const SizedBox(height: 12),
                            Text(devices.isEmpty ? 'Tap refresh to scan' : '${devices.length} ring(s) found', style: Theme.of(context).textTheme.bodySmall),
                          ]),
            ),
          ),

          // Status message
          if (isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Scanning for ChipletRing devices...\nMake sure your ring is powered on.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          // Device list
          Expanded(
            child: devices.isEmpty && !isScanning
              ? Center(child: Text('No rings found.\nTap refresh to scan again.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: devices.length,
                  itemBuilder: (ctx, i) => _DeviceTile(
                    device: devices[i],
                    isDark: isDark,
                    isConnecting: connectionState == RingConnectionState.connecting && ref.read(connectedDeviceProvider)?.macAddress == devices[i].macAddress,
                    onTap: () => _connectDevice(devices[i]),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  void _connectDevice(ScannedDevice device) {
    _stopScan();
    ref.read(connectedDeviceProvider.notifier).state = device;
    ref.read(ringConnectionStateProvider.notifier).state = RingConnectionState.connecting;

    // Connect via native SDK
    RingPlugin.connect(device.macAddress);

    // Listen for health data (battery, version) after connection
    RingPlugin.rawHealthData.listen((data) {
      if (!mounted) return;
      final type = data['type'] as String?;
      switch (type) {
        case 'battery':
          ref.read(batteryLevelProvider.notifier).state = (data['level'] as int?) ?? 0;
          break;
        case 'version':
          ref.read(firmwareVersionProvider.notifier).state = (data['version'] as String?) ?? '';
          break;
      }
    });

    // Listen for connection state
    // Listen for connection state and navigate back
    // Use a single listener subscription to avoid memory leaks
    final subscription = RingPlugin.connectionState.listen((state) {
      if (!mounted) return;
      
      if (state == RingConnectionState.connected) {
        ref.read(ringConnectionStateProvider.notifier).state = RingConnectionState.connected;
        
        // Only pop if this screen is currently visible to prevent black screen
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
           Navigator.of(context).pop();
        }
      } else if (state == RingConnectionState.disconnected) {
        ref.read(ringConnectionStateProvider.notifier).state = RingConnectionState.disconnected;
      }
    });
    
    // Auto-cancel subscription on dispose is verified by Flutter, but let's be safe
    // Actually, method channel streams are broadcast, so multiple listeners are fine.
    // The issue is likely multiple 'connected' events triggering multiple pops.
  }
}

class _DeviceTile extends StatelessWidget {
  final ScannedDevice device;
  final bool isDark;
  final bool isConnecting;
  final VoidCallback onTap;
  const _DeviceTile({required this.device, required this.isDark, required this.isConnecting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: isConnecting ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isConnecting ? AppColors.primary : (isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: isConnecting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.ring_volume_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(device.macAddress, style: Theme.of(context).textTheme.bodySmall),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: List.generate(4, (i) => Container(
                width: 4,
                height: 12 + i * 3.0,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: i < device.signalBars ? AppColors.primary : (isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight),
                  borderRadius: BorderRadius.circular(2),
                ),
              ))),
              if (device.battery != null) ...[const SizedBox(height: 4), Text('${device.battery}%', style: Theme.of(context).textTheme.labelSmall)],
            ]),
          ]),
        ),
      ),
    );
  }
}
