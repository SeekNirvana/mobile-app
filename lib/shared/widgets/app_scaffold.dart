import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

class AppScaffold extends StatelessWidget {
  final Widget child;

  const AppScaffold({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/journal')) {
      return 1;
    }
    if (location.startsWith('/guides')) {
      return 2;
    }
    if (location.startsWith('/profile') ||
        location.startsWith('/capabilities') ||
        location.startsWith('/about') ||
        location.startsWith('/rewards') ||
        location.startsWith('/wallet') ||
        location.startsWith('/badges')) {
      return 3;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final index = _currentIndex(context);
    final location = GoRouterState.of(context).uri.toString();
    final canPop = GoRouter.of(context).canPop();
    final showBottomNav =
        location == '/' ||
        location.startsWith('/journal') ||
        location.startsWith('/guides') ||
        location.startsWith('/profile') ||
        location.startsWith('/rewards') ||
        location.startsWith('/wallet') ||
        location.startsWith('/badges');
    final shouldConfirmExit =
        !canPop &&
        (location == '/' ||
            location == '/journal' ||
            location == '/guides' ||
            location == '/profile');

    return PopScope(
      canPop: !shouldConfirmExit,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !shouldConfirmExit) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Close SeekNirvana?'),
              content: const Text(
                'Do you really want to close the app right now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Stay'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
        if (shouldExit == true) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: showBottomNav,
        body: child,
        bottomNavigationBar: showBottomNav
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isDark ? AppColors.elevatedDark : AppColors.cardLight)
                            .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: isDark
                          ? AppColors.cardBorderDark
                          : AppColors.cardBorderLight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.32 : 0.12,
                        ),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _NavItem(
                          icon: Icons.space_dashboard_rounded,
                          label: 'Home',
                          isSelected: index == 0,
                          onTap: () => context.go('/'),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.menu_book_rounded,
                          label: 'Journal',
                          isSelected: index == 1,
                          onTap: () => context.go('/journal'),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.auto_awesome_rounded,
                          label: 'Guides',
                          isSelected: index == 2,
                          onTap: () => context.go('/guides'),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.person_rounded,
                          label: 'Profile',
                          isSelected: index == 3,
                          onTap: () => context.go('/profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isSelected ? AppColors.gold : AppColors.primary;
    final textColor = isSelected
        ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.14),
                    AppColors.green.withValues(alpha: 0.12),
                  ],
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: activeColor),
            const SizedBox(height: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: textColor,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
