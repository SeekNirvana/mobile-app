import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/theme_provider.dart';
import 'services/ring_data_service.dart';
import 'services/ring_connection_service.dart';
import 'plugins/ring_sdk/ring_plugin.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  
  // Request Bluetooth permission early on iOS to ensure BCLRingSDK can initialize
  _requestInitialBluetoothPermission();
  
  runApp(const ProviderScope(child: SeekNirvanaApp()));
}

/// Request Bluetooth permission on app startup for iOS
/// This ensures the BCLRingSDK can initialize properly
void _requestInitialBluetoothPermission() async {
  if (Platform.isIOS) {
    // Small delay to ensure app is fully initialized
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await RingPlugin.requestBluetoothPermission();
    } catch (e) {
      debugPrint('[Main] Error requesting Bluetooth permission: $e');
    }
  }
}

class SeekNirvanaApp extends ConsumerWidget {
  const SeekNirvanaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Initialize standard services
    ref.watch(ringDataServiceProvider);
    // Initialize connection service for auto-reconnect
    ref.watch(ringConnectionServiceProvider);

    return MaterialApp.router(
      title: 'SeekNirvana',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
