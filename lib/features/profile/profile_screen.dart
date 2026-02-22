import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/ring_provider.dart';
import '../../providers/theme_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';
import '../../plugins/ring_sdk/models/ring_connection_state.dart';
import '../../services/feature_detection_service.dart';
import 'capabilities_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(ringConnectionStateProvider);
    final device = ref.watch(connectedDeviceProvider);
    final battery = ref.watch(batteryLevelProvider);
    final firmware = ref.watch(firmwareVersionProvider);
    final serialNumber = ref.watch(serialNumberProvider);
    final rssi = ref.watch(rssiProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Start RSSI monitoring when connected
    ref.listen(ringConnectionStateProvider, (previous, current) {
      if (current == RingConnectionState.connected) {
        RingPlugin.startReadRSSI();
      } else if (previous == RingConnectionState.connected) {
        RingPlugin.stopReadRSSI();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Profile', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),

            // User
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusXL), border: Border.all(color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight)),
              child: Row(children: [
                CircleAvatar(radius: 30, backgroundColor: AppColors.primary.withValues(alpha: 0.2), child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 32)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SeekNirvana User', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text('Tap to set up your profile', style: Theme.of(context).textTheme.bodySmall),
                ])),
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
              ]),
            ),
            const SizedBox(height: 16),

            // Device
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusXL), border: Border.all(color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Device', style: Theme.of(context).textTheme.titleLarge),
                    Row(
                      children: [
                        if (device != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(device.name, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () {
                             RingPlugin.getVersion();
                             RingPlugin.getBattery();
                          },
                          tooltip: 'Refresh Info',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoRow(label: 'Status', value: connectionState.label, icon: Icons.bluetooth_rounded),
                const Divider(height: 16),
                if (device != null) ...[
                  _InfoRow(label: 'MAC Address', value: device.macAddress, icon: Icons.fingerprint_rounded),
                  const Divider(height: 16),
                  _InfoRow(label: 'Signal Strength', value: '${device.rssi} dBm', icon: Icons.signal_cellular_alt_rounded),
                  const Divider(height: 16),
                ],
                _InfoRow(label: 'Battery', value: battery > 0 ? '$battery%' : '--', icon: Icons.battery_std_rounded),
                const Divider(height: 16),
                _InfoRow(label: 'Firmware', value: firmware.isNotEmpty ? firmware : '--', icon: Icons.system_update_rounded),
                const Divider(height: 16),
                _InfoRow(
                  label: 'Serial Number', 
                  value: serialNumber.isNotEmpty ? serialNumber : '--', 
                  icon: Icons.confirmation_number_rounded,
                  action: serialNumber.isEmpty && device != null
                    ? IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () => RingPlugin.getSerialNumber(),
                        tooltip: 'Read Serial Number',
                      )
                    : null,
                ),
                const Divider(height: 16),
                _RssiIndicator(rssi: rssi),
                const Divider(height: 16),
                _InfoRow(
                  label: 'Capabilities', 
                  value: 'View All',
                  icon: Icons.list_alt,
                  action: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CapabilitiesScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('View'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Extended Features (HID, etc.)
            if (FeatureDetectionService.hasExtendedFeatures)
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                  border: Border.all(color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ring Features', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    
                    // HID Settings (if supported)
                    if (FeatureDetectionService.supportsAnyHID) ...[
                      _SettingTile(
                        icon: Icons.touch_app_rounded,
                        label: 'Gesture Control (HID)',
                        subtitle: '${FeatureDetectionService.supportedTouchFeatures.length + FeatureDetectionService.supportedGestureFeatures.length} features available',
                        onTap: () => _showHIDSettings(context),
                      ),
                      const Divider(height: 24),
                    ],
                    
                    // Vibration/Alarm settings (if supported)
                    if (FeatureDetectionService.supportsVibration) ...[
                      _SettingTile(
                        icon: Icons.vibration_rounded,
                        label: 'Vibration & Alarms',
                        subtitle: 'Set custom vibrations',
                        onTap: () => _showVibrationSettings(context),
                      ),
                      const Divider(height: 24),
                    ],
                    
                    // Sport Mode (if supported)
                    if (FeatureDetectionService.supportsSportMode) ...[
                      _SettingTile(
                        icon: Icons.directions_run_rounded,
                        label: 'Sport Mode',
                        subtitle: 'Track your workouts',
                        onTap: () {},
                      ),
                      const Divider(height: 24),
                    ],
                    
                    // ECG (if supported)
                    if (FeatureDetectionService.supportsECG) ...[
                      _SettingTile(
                        icon: Icons.monitor_heart_rounded,
                        label: 'ECG Recording',
                        subtitle: 'Record electrocardiogram',
                        onTap: () {},
                      ),
                      const Divider(height: 24),
                    ],
                    
                    // Voice Recording (if supported)
                    if (FeatureDetectionService.supportsVoiceRecording) ...[
                      _SettingTile(
                        icon: Icons.mic_rounded,
                        label: 'Voice Recording',
                        subtitle: 'Record audio memos',
                        onTap: () {},
                      ),
                      const Divider(height: 24),
                    ],
                    
                    // Show capabilities summary
                    _CapabilitySummary(),
                  ],
                ),
              ),

            // Settings
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusXL), border: Border.all(color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.dark_mode_rounded, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Dark Mode', style: Theme.of(context).textTheme.bodyMedium)),
                  Switch(value: themeMode == ThemeMode.dark, activeThumbColor: AppColors.primary, onChanged: (val) {
                    ref.read(themeModeProvider.notifier).state = val ? ThemeMode.dark : ThemeMode.light;
                  }),
                ]),
                const Divider(height: 24),
                _SettingTile(icon: Icons.notifications_rounded, label: 'Notifications', subtitle: null, onTap: () {}),
                const Divider(height: 24),
                _SettingTile(icon: Icons.flag_rounded, label: 'Step Goal', subtitle: null, onTap: () {}),
                const Divider(height: 24),
                _SettingTile(icon: Icons.info_outline_rounded, label: 'About', subtitle: null, onTap: () {}),
              ]),
            ),
            const SizedBox(height: 24),

            Text('SeekNirvana v0.1.0', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Widget? action;
  const _InfoRow({required this.label, required this.value, required this.icon, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: AppColors.textSecondaryDark),
      const SizedBox(width: 10),
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
      const Spacer(),
      if (action != null) ...[
        action!,
        const SizedBox(width: 8),
      ],
      Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}

class _RssiIndicator extends StatelessWidget {
  final int rssi;
  
  const _RssiIndicator({required this.rssi});
  
  @override
  Widget build(BuildContext context) {
    final signalStrength = _getSignalStrength(rssi);
    final color = _getSignalColor(rssi);
    final bars = _getSignalBars(rssi);
    
    return Row(
      children: [
        Icon(
          Icons.signal_cellular_alt_rounded,
          size: 18,
          color: rssi != 0 ? color : AppColors.textSecondaryDark,
        ),
        const SizedBox(width: 10),
        Text(
          'Signal Strength',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Spacer(),
        // Signal bars
        Row(
          children: List.generate(4, (index) {
            return Container(
              width: 4,
              height: 8 + index * 3.0,
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: index < bars ? color : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(width: 8),
        Text(
          rssi != 0 ? '$rssi dBm ($signalStrength)' : '--',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: rssi != 0 ? color : null,
          ),
        ),
      ],
    );
  }
  
  String _getSignalStrength(int rssi) {
    if (rssi == 0) return 'Unknown';
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    if (rssi >= -80) return 'Weak';
    return 'Poor';
  }
  
  Color _getSignalColor(int rssi) {
    if (rssi == 0) return Colors.grey;
    if (rssi >= -60) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
  
  int _getSignalBars(int rssi) {
    if (rssi == 0) return 0;
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  const _SettingTile({required this.icon, required this.label, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
        ],
      ),
    );
  }
}

class _CapabilitySummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final summary = FeatureDetectionService.supportedFeaturesSummary;
    if (summary.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(
          'Supported Features:',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...summary.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key}: ',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value.join(', '),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// Extension methods for ProfileScreen
extension on ProfileScreen {
  void _showHIDSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const HIDSettingsSheet(),
    );
  }
  
  void _showVibrationSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const VibrationSettingsSheet(),
    );
  }
}

// HID Settings Sheet
class HIDSettingsSheet extends ConsumerWidget {
  const HIDSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gesture Control (HID)',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure your ring to control your device with gestures',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          
          // Touch Mode Settings
          if (FeatureDetectionService.supportedTouchFeatures.isNotEmpty) ...[
            Text(
              'Touch Gestures',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...FeatureDetectionService.supportedTouchFeatures.map((feature) {
              return _HIDOptionTile(
                icon: Icons.touch_app,
                label: feature,
                onTap: () => _setHIDTouchMode(context, feature),
              );
            }),
            const SizedBox(height: 24),
          ],
          
          // Gesture Mode Settings
          if (FeatureDetectionService.supportedGestureFeatures.isNotEmpty) ...[
            Text(
              'Air Gestures',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...FeatureDetectionService.supportedGestureFeatures.map((feature) {
              return _HIDOptionTile(
                icon: Icons.waving_hand,
                label: feature,
                onTap: () => _setHIDGestureMode(context, feature),
              );
            }),
          ],
          
          const SizedBox(height: 24),
          
          // Disable button
          FilledButton.icon(
            onPressed: () => _disableHID(context),
            icon: const Icon(Icons.block),
            label: const Text('Disable All Gestures'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  void _setHIDTouchMode(BuildContext context, String mode) async {
    int touchMode = 0xFF; // Default: disabled
    switch (mode) {
      case 'Music':
        touchMode = 0x01;
        break;
      case 'Photo':
        touchMode = 0x02;
        break;
      case 'Video':
        touchMode = 0x03;
        break;
    }
    
    try {
      await RingPlugin.setHIDMode(touchMode: touchMode, gestureMode: 0xFF);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Touch mode set to: $mode')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set HID mode: $e')),
        );
      }
    }
  }
  
  void _setHIDGestureMode(BuildContext context, String mode) async {
    // Map gesture modes to appropriate values
    int gestureMode = 0xFF;
    // Implementation depends on specific gesture types
    
    try {
      await RingPlugin.setHIDMode(touchMode: 0xFF, gestureMode: gestureMode);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gesture mode set to: $mode')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set HID mode: $e')),
        );
      }
    }
  }
  
  void _disableHID(BuildContext context) async {
    try {
      await RingPlugin.setHIDMode(touchMode: 0xFF, gestureMode: 0xFF);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All gestures disabled')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to disable HID: $e')),
        );
      }
    }
  }
}

class _HIDOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  
  const _HIDOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}

// Vibration Settings Sheet
class VibrationSettingsSheet extends ConsumerWidget {
  const VibrationSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vibration & Alarms',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Quick vibration test
          ListTile(
            leading: const Icon(Icons.vibration),
            title: const Text('Test Vibration'),
            subtitle: const Text('2 second strong vibration'),
            onTap: () {
              RingPlugin.vibrate(seconds: 2);
            },
          ),
          
          const Divider(),
          
          // Alarm settings placeholder
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Set Alarm'),
            subtitle: const Text('Coming soon'),
            enabled: false,
            onTap: () {},
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
