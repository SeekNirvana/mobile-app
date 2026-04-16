import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/ring_provider.dart';
import '../../providers/theme_provider.dart';
import '../../plugins/ring_sdk/ring_plugin.dart';
import '../../plugins/ring_sdk/models/ring_connection_state.dart';
import '../../services/feature_detection_service.dart';
import '../../services/guide_model_manager.dart';
import '../../services/profile_preferences_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(ringConnectionStateProvider);
    final device = ref.watch(connectedDeviceProvider);
    final battery = ref.watch(batteryLevelProvider);
    final firmware = ref.watch(firmwareVersionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final guideModelManager = ref.watch(guideModelManagerProvider);
    final profilePreferences = ref.watch(profilePreferencesProvider);
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
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            Text(
              'Profile',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Shape your setup for sleep, private AI, and a calmer daily rhythm.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 20),

            _ProfileHeroCard(
              displayName: profilePreferences.displayName,
              profileSummary: profilePreferences.profileSummary,
              connectionState: connectionState.label,
              battery: battery,
              guideReady: guideModelManager.allModelsReady,
              notificationsEnabled: profilePreferences.notificationsEnabled,
              onEditProfile: () =>
                  _showProfileSettings(context, profilePreferences),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _ProfileMetricTile(
                    icon: Icons.height_rounded,
                    label: 'Height',
                    value: '${profilePreferences.heightCm} cm',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProfileMetricTile(
                    icon: Icons.monitor_weight_rounded,
                    label: 'Weight',
                    value: '${profilePreferences.weightKg} kg',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProfileMetricTile(
                    icon: Icons.flag_rounded,
                    label: 'Step Goal',
                    value: profilePreferences.stepGoal.toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _SectionCard(
              title: 'Device Snapshot',
              subtitle:
                  'Your ring connection, firmware, and core sync details at a glance.',
              child: Column(
                children: [
                  Row(
                    children: [
                      if (device != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                          ),
                          child: Text(
                            device.name,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: () {
                          RingPlugin.getVersion();
                          RingPlugin.getBattery();
                        },
                        tooltip: 'Refresh ring info',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    label: 'Status',
                    value: connectionState.label,
                    icon: Icons.bluetooth_rounded,
                  ),
                  const Divider(height: 18),
                  _InfoRow(
                    label: 'Battery',
                    value: battery > 0 ? '$battery%' : '--',
                    icon: Icons.battery_std_rounded,
                  ),
                  const Divider(height: 18),
                  _InfoRow(
                    label: 'Firmware',
                    value: firmware.isNotEmpty ? firmware : '--',
                    icon: Icons.system_update_rounded,
                  ),
                  if (device != null) ...[
                    const Divider(height: 18),
                    _InfoRow(
                      label: 'Signal',
                      value: '${device.rssi} dBm',
                      icon: Icons.signal_cellular_alt_rounded,
                    ),
                    const Divider(height: 18),
                    _InfoRow(
                      label: 'MAC',
                      value: device.macAddress,
                      icon: Icons.fingerprint_rounded,
                    ),
                  ],
                  const Divider(height: 22),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () => context.push('/capabilities'),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('View Capabilities'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Extended Features (HID, etc.)
            if (FeatureDetectionService.hasExtendedFeatures)
              _SectionCard(
                title: 'Ring Features',
                subtitle:
                    'The controls already supported by this build, plus the hardware features that are still being wired up.',
                child: Column(
                  children: [
                    // HID Settings (if supported)
                    if (FeatureDetectionService.supportsAnyHID) ...[
                      _SettingTile(
                        icon: Icons.touch_app_rounded,
                        label: 'Gesture Control (HID)',
                        subtitle:
                            '${FeatureDetectionService.supportedTouchFeatures.length + FeatureDetectionService.supportedGestureFeatures.length} features available',
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
                        onTap: null,
                        trailingLabel: 'Soon',
                      ),
                      const Divider(height: 24),
                    ],

                    if (FeatureDetectionService.supportsECG) ...[
                      _SettingTile(
                        icon: Icons.monitor_heart_rounded,
                        label: 'ECG Recording',
                        subtitle: 'Record electrocardiogram',
                        onTap: null,
                        trailingLabel: 'Soon',
                      ),
                      const Divider(height: 24),
                    ],

                    if (FeatureDetectionService.supportsVoiceRecording) ...[
                      _SettingTile(
                        icon: Icons.mic_rounded,
                        label: 'Voice Recording',
                        subtitle: 'Record audio memos',
                        onTap: null,
                        trailingLabel: 'Soon',
                      ),
                      const Divider(height: 24),
                    ],

                    _CapabilitySummary(),
                  ],
                ),
              ),
            if (FeatureDetectionService.hasExtendedFeatures)
              const SizedBox(height: 16),

            _SectionCard(
              title: 'Preferences',
              subtitle:
                  'Everything personal to your experience, from reminders to local AI storage.',
              child: Column(
                children: [
                  _SwitchSettingRow(
                    icon: Icons.notifications_rounded,
                    label: 'Notifications',
                    subtitle: 'Daily reminders and gentle nudges',
                    value: profilePreferences.notificationsEnabled,
                    onChanged: profilePreferences.setNotificationsEnabled,
                  ),
                  const Divider(height: 24),
                  _SwitchSettingRow(
                    icon: Icons.dark_mode_rounded,
                    label: 'Dark Mode',
                    subtitle: 'Use the darker interface throughout the app',
                    value: themeMode == ThemeMode.dark,
                    onChanged: (val) {
                      ref.read(themeModeProvider.notifier).state = val
                          ? ThemeMode.dark
                          : ThemeMode.light;
                    },
                  ),
                  const Divider(height: 24),
                  _SettingTile(
                    icon: Icons.folder_rounded,
                    label: 'Local AI Storage',
                    subtitle:
                        guideModelManager.storageDirectoryPath ??
                        'Loading local folder...',
                    onTap: () =>
                        _showModelStorageSettings(context, guideModelManager),
                  ),
                  const Divider(height: 24),
                  _SettingTile(
                    icon: Icons.info_outline_rounded,
                    label: 'About SeekNirvana',
                    subtitle:
                        'Mission, privacy, hardware, and the path from attention to intention',
                    onTap: () => context.push('/about'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'SeekNirvana v0.1.0',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  final String displayName;
  final String profileSummary;
  final String connectionState;
  final int battery;
  final bool guideReady;
  final bool notificationsEnabled;
  final VoidCallback onEditProfile;

  const _ProfileHeroCard({
    required this.displayName,
    required this.profileSummary,
    required this.connectionState,
    required this.battery,
    required this.guideReady,
    required this.notificationsEnabled,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.92),
            AppColors.sleep.withValues(alpha: 0.86),
            AppColors.accent.withValues(alpha: 0.70),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXXL),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sleep with intention. Wake with clarity.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onEditProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            profileSummary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroChip(icon: Icons.bluetooth_rounded, label: connectionState),
              _HeroChip(
                icon: Icons.battery_std_rounded,
                label: battery > 0 ? '$battery% battery' : 'Battery pending',
              ),
              _HeroChip(
                icon: Icons.notifications_rounded,
                label: notificationsEnabled
                    ? 'Notifications on'
                    : 'Notifications off',
              ),
              _HeroChip(
                icon: Icons.memory_rounded,
                label: guideReady ? 'Private AI ready' : 'AI setup pending',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SwitchSettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchSettingRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final String? trailingLabel;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final bodyColor = Theme.of(context).textTheme.bodySmall?.color;
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isEnabled ? null : bodyColor?.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isEnabled
                        ? null
                        : bodyColor?.withValues(alpha: 0.72),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: bodyColor?.withValues(alpha: isEnabled ? 1 : 0.72),
                    ),
                  ),
              ],
            ),
          ),
          if (trailingLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                trailingLabel!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: bodyColor),
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
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
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
  void _showProfileSettings(
    BuildContext context,
    ProfilePreferencesService preferences,
  ) {
    final nameController = TextEditingController(text: preferences.displayName);
    final heightController = TextEditingController(
      text: preferences.heightCm.toString(),
    );
    final weightController = TextEditingController(
      text: preferences.weightKg.toString(),
    );
    final stepGoalController = TextEditingController(
      text: preferences.stepGoal.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            top: 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(AppConstants.radiusXXL),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile & Goals',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Set the basics that shape your dashboard and daily targets.',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodySmall?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: heightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Height (cm)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: weightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Weight (kg)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: stepGoalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Daily step goal',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        final height = int.tryParse(heightController.text) ?? 0;
                        final weight = int.tryParse(weightController.text) ?? 0;
                        final stepGoal =
                            int.tryParse(stepGoalController.text) ?? 0;

                        if (height < 100 ||
                            height > 250 ||
                            weight < 25 ||
                            weight > 300 ||
                            stepGoal < 1000 ||
                            stepGoal > 50000) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Enter a realistic height, weight, and step goal.',
                              ),
                            ),
                          );
                          return;
                        }

                        await preferences.updateProfile(
                          displayName: nameController.text,
                          heightCm: height,
                          weightKg: weight,
                          stepGoal: stepGoal,
                        );
                        if (context.mounted) {
                          Navigator.of(sheetContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Profile updated.')),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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

  void _showModelStorageSettings(
    BuildContext context,
    GuideModelManager manager,
  ) {
    final controller = TextEditingController(
      text:
          manager.storageDirectoryPath ??
          manager.defaultStorageDirectoryPath ??
          '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Local AI Storage Folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'By default, SeekNirvana uses a local seeknirvana folder with `models` and `chats` subfolders for Luna, Nova, and chat history. You can point the app at a different writable root folder here.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Folder path',
                  hintText: '/storage/.../seeknirvana',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Default: ${manager.defaultStorageDirectoryPath ?? '--'}',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await manager.resetStorageDirectory();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Local AI storage reset to the default seeknirvana folder.',
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not reset model folder: $error'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await manager.updateStorageDirectory(controller.text);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Local AI storage folder updated.'),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not update model folder: $error'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Touch mode set to: $mode')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to set HID mode: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gesture mode set to: $mode')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to set HID mode: $e')));
      }
    }
  }

  void _disableHID(BuildContext context) async {
    try {
      await RingPlugin.setHIDMode(touchMode: 0xFF, gestureMode: 0xFF);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All gestures disabled')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to disable HID: $e')));
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
