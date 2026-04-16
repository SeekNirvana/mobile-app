import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(title: const Text('About SeekNirvana')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: isDark ? 0.80 : 0.92),
                  AppColors.sleep.withValues(alpha: isDark ? 0.74 : 0.88),
                  AppColors.accent.withValues(alpha: isDark ? 0.62 : 0.70),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppConstants.radiusXXL),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    'Seek Nirvana',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'From Attention to Intention',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'SeekNirvana brings together lucid dreaming, biometrics, sleep intelligence, and private AI to help people live with more calm, clarity, and self-direction.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Ancient self-mastery, translated into a wearable and an app that work quietly in the background of everyday life.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(
                child: _AboutStatCard(
                  label: 'HRV',
                  value: '512Hz',
                  icon: Icons.favorite_rounded,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _AboutStatCard(
                  label: 'Battery',
                  value: '7 days',
                  icon: Icons.battery_charging_full_rounded,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _AboutStatCard(
                  label: 'AI',
                  value: 'Edge',
                  icon: Icons.memory_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _AboutSectionCard(
            title: 'What SeekNirvana Builds',
            subtitle:
                'The product is designed around a few core experiences that work together rather than feeling like isolated features.',
            items: [
              _AboutItem(
                icon: Icons.nightlight_round,
                title: 'Lucid Dreaming',
                description:
                    'Subtle dream cues and REM-aware timing help users become more conscious inside sleep itself.',
              ),
              _AboutItem(
                icon: Icons.monitor_heart_rounded,
                title: 'Vitality Tracking',
                description:
                    'HRV, temperature, movement, and recovery patterns turn raw body signals into clear feedback.',
              ),
              _AboutItem(
                icon: Icons.auto_awesome_rounded,
                title: 'Mindful AI',
                description:
                    'Private on-device guidance helps translate patterns into small, useful next steps instead of noise.',
              ),
              _AboutItem(
                icon: Icons.shield_moon_rounded,
                title: 'Sacred Privacy',
                description:
                    'The experience is built around ownership, local intelligence, and less dependence on the cloud.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _AboutSectionCard(
            title: 'How the Journey Works',
            subtitle:
                'The experience is meant to feel calm and almost invisible: sense first, interpret second, guide gently.',
            items: [
              _AboutItem(
                icon: Icons.blur_on_rounded,
                title: 'Quiet the signal',
                description:
                    'The ring watches for tension, coherence, and sleep transitions without demanding attention.',
              ),
              _AboutItem(
                icon: Icons.insights_rounded,
                title: 'Read the body',
                description:
                    'Biometric patterns surface the moments where stress, recovery, and sleep quality start to diverge.',
              ),
              _AboutItem(
                icon: Icons.self_improvement_rounded,
                title: 'Choose with intention',
                description:
                    'The app answers with gentle prompts, practices, and context-aware guidance that help users respond rather than react.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _AboutSectionCard(
            title: 'Why It Exists',
            subtitle:
                'SeekNirvana is aimed at people who want better sleep, better self-awareness, and technology that feels aligned instead of extractive.',
            items: [
              _AboutItem(
                icon: Icons.psychology_alt_rounded,
                title: 'More inner clarity',
                description:
                    'A calmer relationship with stress, dreams, focus, and the choices that shape everyday life.',
              ),
              _AboutItem(
                icon: Icons.bedtime_rounded,
                title: 'Better restorative sleep',
                description:
                    'Sleep is treated as the foundation for cognition, recovery, and emotional steadiness.',
              ),
              _AboutItem(
                icon: Icons.lock_rounded,
                title: 'Less extraction',
                description:
                    'The product direction favors one-time ownership, local intelligence, and respect for personal data.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : AppColors.cardLight,
              borderRadius: BorderRadius.circular(AppConstants.radiusXL),
              border: Border.all(
                color: isDark
                    ? AppColors.cardBorderDark
                    : AppColors.cardBorderLight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'SeekNirvana v0.1.0',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Inspired by the story and product direction on seeknirvana.com.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _AboutStatCard({
    required this.label,
    required this.value,
    required this.icon,
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
          Icon(icon, size: 18, color: AppColors.primaryLight),
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

class _AboutSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_AboutItem> items;

  const _AboutSectionCard({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
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
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < items.length; index++) ...[
            _AboutFeatureRow(item: items[index]),
            if (index < items.length - 1) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _AboutItem {
  final IconData icon;
  final String title;
  final String description;

  const _AboutItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _AboutFeatureRow extends StatelessWidget {
  final _AboutItem item;

  const _AboutFeatureRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          child: Icon(item.icon, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                item.description,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
