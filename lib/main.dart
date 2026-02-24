import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/riverpod_providers.dart';

import 'providers/settings_notifier.dart';

import 'router.dart';
import 'screens/welcome_tour_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Laptop Dashboard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      routerConfig: router,
    );
  }
}

class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({super.key});

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  Future<void> _initApp() async {
    await ref.read(settingsProvider.notifier).loadSettings();

    ref
        .read(statsProvider.notifier)
        .updateFromSettings(ref.read(settingsProvider));
    ref
        .read(uploadProvider.notifier)
        .initialize(ref.read(settingsProvider).laptopIp);
    ref
        .read(notificationProvider.notifier)
        .initializeApiService(ref.read(settingsProvider).laptopIp);

    ref.listen<SettingsState>(settingsProvider, (previous, next) {
      ref.read(statsProvider.notifier).updateFromSettings(next);
      ref
          .read(notificationProvider.notifier)
          .initializeApiService(next.laptopIp);
      ref.read(uploadProvider.notifier).updateApiService(next.laptopIp);
    });

    ref.read(logsProvider.notifier).addLog('Dashboard started');

    await ref
        .read(notificationProvider.notifier)
        .initialize(
          onNotificationTap: _handleNotificationTap,
          onNotificationAction: _handleNotificationAction,
        );
    ref
        .read(notificationProvider.notifier)
        .initializeApiService(ref.read(settingsProvider).laptopIp);

    await _checkAndShowWelcomeTour();
  }

  void _handleNotificationTap(String? payload) {
    if (payload == 'file_transfer') {
      router.go('/files');
    }
  }

  void _handleNotificationAction(String action) {
    if (action == 'download') {
      router.go('/files');
    }
  }

  Future<void> _checkAndShowWelcomeTour() async {
    if (ref.read(settingsProvider).hasSeenWelcomeTour) return;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WelcomeTourScreen()));
    await ref.read(settingsProvider.notifier).setHasSeenWelcomeTour(true);
    ref.read(logsProvider.notifier).addLog('Welcome tour completed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final settings = ref.read(settingsProvider);
      ref
          .read(statsProvider.notifier)
          .onAppResumed(settings.pollingIntervalSeconds);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
