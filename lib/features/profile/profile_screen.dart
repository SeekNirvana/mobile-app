import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/ring_provider.dart';
import '../../providers/theme_provider.dart';
import '../../plugins/ring_sdk/models/scanned_device.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(ringConnectionStateProvider);
    final device = ref.watch(connectedDeviceProvider);
    final battery = ref.watch(batteryLevelProvider);
    final firmware = ref.watch(firmwareVersionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              ]),
            ),
            const SizedBox(height: 16),

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
                _SettingTile(icon: Icons.notifications_rounded, label: 'Notifications', onTap: () {}),
                const Divider(height: 24),
                _SettingTile(icon: Icons.flag_rounded, label: 'Step Goal', onTap: () {}),
                const Divider(height: 24),
                _SettingTile(icon: Icons.info_outline_rounded, label: 'About', onTap: () {}),
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
  const _InfoRow({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: AppColors.textSecondaryDark),
      const SizedBox(width: 10),
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
      const Spacer(),
      Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SettingTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: Row(children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
    ]));
  }
}
