import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../services/feature_detection_service.dart';

/// Screen showing all ring capabilities
class CapabilitiesScreen extends ConsumerWidget {
  const CapabilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ring Capabilities'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Ring Supports:',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'These are the features available on your connected ring.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Core Features (Always available)
          _CapabilitySection(
            title: 'Core Features',
            icon: Icons.favorite,
            color: Colors.red,
            capabilities: [
              _CapabilityItem(
                icon: Icons.favorite,
                name: 'Heart Rate',
                description: 'PPG-based heart rate monitoring',
                supported: true,
              ),
              _CapabilityItem(
                icon: Icons.water_drop,
                name: 'SpO2',
                description: 'Blood oxygen saturation',
                supported: true,
              ),
              _CapabilityItem(
                icon: Icons.thermostat,
                name: 'Temperature',
                description: 'Skin temperature measurement',
                supported: true,
              ),
              _CapabilityItem(
                icon: Icons.directions_walk,
                name: 'Step Count',
                description: 'Daily step tracking',
                supported: true,
              ),
              _CapabilityItem(
                icon: Icons.bedtime,
                name: 'Sleep Tracking',
                description: 'Sleep stage analysis',
                supported: true,
              ),
            ],
          ),
          
          // Health Features
          _CapabilitySection(
            title: 'Advanced Health',
            icon: Icons.health_and_safety,
            color: Colors.green,
            capabilities: [
              _CapabilityItem(
                icon: Icons.speed,
                name: 'Blood Pressure',
                description: FeatureDetectionService.supportsPPGBloodPressure 
                  ? 'PPG-based estimation (Android)' 
                  : 'Native SDK support',
                supported: FeatureDetectionService.supportsBloodPressure,
              ),
              _CapabilityItem(
                icon: Icons.bloodtype,
                name: 'Blood Glucose',
                description: 'Blood sugar monitoring',
                supported: FeatureDetectionService.supportsBloodGlucose,
              ),
              _CapabilityItem(
                icon: Icons.monitor_heart,
                name: 'ECG',
                description: 'Electrocardiogram recording',
                supported: FeatureDetectionService.supportsECG,
              ),
            ],
          ),
          
          // HID Features
          if (FeatureDetectionService.supportsAnyHID)
            _CapabilitySection(
              title: 'Gesture Control (HID)',
              icon: Icons.touch_app,
              color: Colors.blue,
              capabilities: [
                if (FeatureDetectionService.supportsTouchPhoto)
                  _CapabilityItem(
                    icon: Icons.camera_alt,
                    name: 'Touch - Photo',
                    description: 'Tap to take photo',
                    supported: true,
                  ),
                if (FeatureDetectionService.supportsTouchVideo)
                  _CapabilityItem(
                    icon: Icons.videocam,
                    name: 'Touch - Video',
                    description: 'Tap to control video',
                    supported: true,
                  ),
                if (FeatureDetectionService.supportsTouchMusic)
                  _CapabilityItem(
                    icon: Icons.music_note,
                    name: 'Touch - Music',
                    description: 'Tap to control music',
                    supported: true,
                  ),
                if (FeatureDetectionService.supportsPinchPhoto)
                  _CapabilityItem(
                    icon: Icons.camera_enhance,
                    name: 'Gesture - Pinch Photo',
                    description: 'Pinch to take photo',
                    supported: true,
                  ),
                if (FeatureDetectionService.supportsGestureMusic)
                  _CapabilityItem(
                    icon: Icons.audiotrack,
                    name: 'Gesture - Music Control',
                    description: 'Air gestures for music',
                    supported: true,
                  ),
              ],
            ),
          
          // Hardware Features
          _CapabilitySection(
            title: 'Hardware Features',
            icon: Icons.hardware,
            color: Colors.orange,
            capabilities: [
              _CapabilityItem(
                icon: Icons.vibration,
                name: 'Vibration / Alarms',
                description: 'Custom vibrations and alarms',
                supported: FeatureDetectionService.supportsVibration,
              ),
              _CapabilityItem(
                icon: Icons.mic,
                name: 'Voice Recording',
                description: 'Audio memo recording',
                supported: FeatureDetectionService.supportsVoiceRecording,
              ),
              _CapabilityItem(
                icon: Icons.sd_storage,
                name: 'File System',
                description: 'Store files on ring',
                supported: FeatureDetectionService.supportsFileSystem,
              ),
              _CapabilityItem(
                icon: Icons.directions_run,
                name: 'Sport Mode',
                description: 'Exercise tracking modes',
                supported: FeatureDetectionService.supportsSportMode,
              ),
            ],
          ),
          
          // Sleep Features
          _CapabilitySection(
            title: 'Sleep Features',
            icon: Icons.nightlight,
            color: Colors.indigo,
            capabilities: [
              _CapabilityItem(
                icon: Icons.bedtime,
                name: 'GoMore Sleep Algorithm',
                description: 'Advanced sleep analysis',
                supported: FeatureDetectionService.supportsGoMoreSleep,
              ),
            ],
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _CapabilitySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_CapabilityItem> capabilities;

  const _CapabilitySection({
    required this.title,
    required this.icon,
    required this.color,
    required this.capabilities,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
            ),
          ),
          child: Column(
            children: capabilities.map((cap) => _CapabilityTile(
              item: cap,
              isDark: isDark,
            )).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  final _CapabilityItem item;
  final bool isDark;

  const _CapabilityTile({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        item.icon,
        color: item.supported ? Colors.green : Colors.grey,
      ),
      title: Text(item.name),
      subtitle: Text(
        item.description,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: item.supported
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'SUPPORTED',
              style: TextStyle(
                color: Colors.green,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'NOT SUPPORTED',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
    );
  }
}

class _CapabilityItem {
  final IconData icon;
  final String name;
  final String description;
  final bool supported;

  _CapabilityItem({
    required this.icon,
    required this.name,
    required this.description,
    required this.supported,
  });
}
