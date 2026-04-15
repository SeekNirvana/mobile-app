import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:seeknirvana/features/home/home_screen.dart';
import 'package:seeknirvana/features/vitals/vitals_screen.dart';
import 'package:seeknirvana/features/sleep/sleep_screen.dart';
import 'package:seeknirvana/features/activities/activities_screen.dart';
import 'package:seeknirvana/features/guides/guides_screen.dart';
import 'package:seeknirvana/features/profile/profile_screen.dart';
import 'package:seeknirvana/features/profile/capabilities_screen.dart';
import 'package:seeknirvana/features/scan/scan_screen.dart';
import 'package:seeknirvana/shared/widgets/app_scaffold.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppScaffold(child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomeScreen()),
        ),
        GoRoute(
          path: '/vitals',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: VitalsScreen()),
        ),
        GoRoute(
          path: '/sleep',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SleepScreen()),
        ),
        GoRoute(
          path: '/activities',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ActivitiesScreen()),
        ),
        GoRoute(
          path: '/guides',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: GuidesScreen()),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ProfileScreen()),
        ),
        GoRoute(
          path: '/capabilities',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CapabilitiesScreen()),
        ),
      ],
    ),
    GoRoute(
      path: '/scan',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ScanScreen(),
    ),
  ],
);
