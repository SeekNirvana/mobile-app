import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/theme_provider.dart';
import 'services/app_startup_service.dart';
import 'services/ring_data_service.dart';
import 'services/ring_connection_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables from .env file
  try {
    await dotenv.load(fileName: ".env");
    debugPrint('[Main] Environment variables loaded from .env');
  } catch (e) {
    debugPrint('[Main] No .env file found or error loading: $e');
    debugPrint('[Main] Using --dart-define or default values instead');
  }
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: SeekNirvanaBootstrap()));
}

class SeekNirvanaBootstrap extends ConsumerStatefulWidget {
  const SeekNirvanaBootstrap({super.key});

  @override
  ConsumerState<SeekNirvanaBootstrap> createState() =>
      _SeekNirvanaBootstrapState();
}

class _SeekNirvanaBootstrapState extends ConsumerState<SeekNirvanaBootstrap> {
  bool _didBootstrap = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    if (_didBootstrap) {
      return;
    }
    _didBootstrap = true;

    unawaited(
      AppStartupService.instance.ensureInitialized().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint('[Main] FlutterGemma initialization failed: $error');
        debugPrint('$stackTrace');
      }),
    );

    try {
      ref.read(ringDataServiceProvider);
    } catch (error, stackTrace) {
      debugPrint('[Main] RingDataService init failed: $error');
      debugPrint('$stackTrace');
    }

    if (Platform.isIOS) {
      debugPrint(
        '[Main] Skipping eager ring connection initialization on iOS startup.',
      );
      return;
    }

    try {
      ref.read(ringConnectionServiceProvider);
    } catch (error, stackTrace) {
      debugPrint('[Main] RingConnectionService init failed: $error');
      debugPrint('$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SeekNirvanaApp();
  }
}

class SeekNirvanaApp extends ConsumerWidget {
  const SeekNirvanaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

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
