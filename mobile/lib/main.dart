import 'dart:ui';

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'theme/brand.dart';
import 'widgets/brand_logo.dart';

final ValueNotifier<String?> _fatalErrorNotifier = ValueNotifier<String?>(null);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _fatalErrorNotifier.value ??= details.exceptionAsString();
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _fatalErrorNotifier.value ??= error.toString();
    return true;
  };
  ErrorWidget.builder = (details) {
    return Material(
      color: BrandColors.canvas,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogoImage(height: 84),
              const SizedBox(height: 14),
              const Icon(
                Icons.error_outline_rounded,
                color: BrandColors.primary,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'Screen Error',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                ApiClient.friendlyError(
                  details.exceptionAsString(),
                  fallback: 'This screen could not load right now. Check your internet connection and try again.',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };
  runApp(RetailSuiteApp(errorNotifier: _fatalErrorNotifier));
}

class RetailSuiteApp extends StatefulWidget {
  final ValueNotifier<String?> errorNotifier;

  const RetailSuiteApp({super.key, required this.errorNotifier});

  @override
  State<RetailSuiteApp> createState() => _RetailSuiteAppState();
}

class _RetailSuiteAppState extends State<RetailSuiteApp> {
  final AppState appState = AppState(baseUrl: 'http://bales.rapidconnect.co.zw');
  bool _ready = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await appState.load();
    } catch (e) {
      _loadError = ApiClient.friendlyError(
        e,
        fallback: 'Check your internet connection and tap Reload to try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _ready = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(
          backgroundColor: BrandColors.canvas,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandLogoImage(height: 92),
                SizedBox(height: 18),
                CircularProgressIndicator(color: BrandColors.primary),
              ],
            ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<String?>(
      valueListenable: widget.errorNotifier,
      builder: (context, fatalError, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'T.One',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: BrandColors.primary),
            scaffoldBackgroundColor: BrandColors.canvas,
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: Colors.black.withOpacity(0.05)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: BrandColors.primary,
                  width: 1.4,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.black,
            ),
          ),
          routes: {
            '/login': (_) => LoginScreen(appState: appState),
            '/register': (_) => RegisterScreen(appState: appState),
            '/home': (_) => HomeScreen(appState: appState),
          },
          home: _buildHome(fatalError),
        );
      },
    );
  }

  Widget _buildHome(String? fatalError) {
    if (fatalError != null) {
      return _AppErrorScreen(
        title: 'App Error',
        message: ApiClient.friendlyError(
          fatalError,
          fallback: 'Something went wrong. Close and reopen the app, then try again.',
        ),
      );
    }
    if (_loadError != null) {
      return _AppErrorScreen(
        title: 'Connection Error',
        message: _loadError!,
        onRetry: () {
          setState(() {
            _ready = false;
            _loadError = null;
          });
          _initialize();
        },
      );
    }
    return appState.isLoggedIn
        ? HomeScreen(appState: appState)
        : LoginScreen(appState: appState);
  }
}

class _AppErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _AppErrorScreen({
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogoImage(height: 90),
              const SizedBox(height: 14),
              const Icon(
                Icons.error_outline_rounded,
                color: BrandColors.primary,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reload'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
