import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/riverpod_providers.dart';
import 'providers/settings_notifier.dart';
import 'screens/dashboard_screen.dart';
import 'screens/file_transfer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/welcome_tour_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Laptop Dashboard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(),
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

    // Listen for settings changes
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
      ref.read(settingsProvider.notifier).setDrawerIndex(1);
    }
  }

  void _handleNotificationAction(String action) {
    if (action == 'download') {
      ref.read(settingsProvider.notifier).setDrawerIndex(1);
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
    final settings = ref.watch(settingsProvider);
    String appBarTitle = switch (settings.drawerIndex) {
      1 => 'File Transfer',
      2 => 'Settings',
      _ => 'Laptop Dashboard',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: settings.drawerIndex,
        children: const [
          DashboardScreen(),
          FileTransferScreen(),
          SettingsScreen(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final settings = ref.watch(settingsProvider);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: const Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Laptop Dashboard',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          _drawerTile(0, Icons.dashboard, 'Dashboard', settings.drawerIndex),
          _drawerTile(
            1,
            Icons.upload_file,
            'File Transfer',
            settings.drawerIndex,
          ),
          _drawerTile(2, Icons.settings, 'Settings', settings.drawerIndex),
        ],
      ),
    );
  }

  Widget _drawerTile(
    int index,
    IconData icon,
    String title,
    int selectedIndex,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: selectedIndex == index,
      onTap: () {
        ref.read(settingsProvider.notifier).setDrawerIndex(index);
        Navigator.pop(context);
      },
    );
  }
}
