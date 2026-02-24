import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/settings_notifier.dart';
import 'providers/stats_notifier.dart';
import 'providers/logs_notifier.dart';
import 'providers/upload_notifier.dart';
import 'providers/notification_notifier.dart';
import 'screens/dashboard_screen.dart';
import 'screens/file_transfer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/welcome_tour_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsNotifier()),
        ChangeNotifierProvider(create: (_) => LogsNotifier()),
        ChangeNotifierProvider(create: (_) => UploadNotifier()),
        ChangeNotifierProvider(create: (_) => NotificationNotifier()),
        ChangeNotifierProxyProvider<SettingsNotifier, StatsNotifier>(
          create: (_) => StatsNotifier(),
          update: (_, settings, stats) => stats!..updateFromSettings(settings),
        ),
      ],
      child: MaterialApp(
        title: 'Laptop Dashboard',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: const MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  Future<void> _initApp() async {
    final settings = context.read<SettingsNotifier>();
    final stats = context.read<StatsNotifier>();
    final logs = context.read<LogsNotifier>();
    final upload = context.read<UploadNotifier>();
    final notifications = context.read<NotificationNotifier>();

    await settings.loadSettings();

    stats.initialize(settings);
    upload.initialize(settings.laptopIp);
    notifications.initializeApiService(settings.laptopIp);

    // Listen for settings changes
    settings.addListener(() {
      stats.updateFromSettings(settings);
      notifications.initializeApiService(settings.laptopIp);
      upload.updateApiService(settings.laptopIp);
    });

    logs.addLog('Dashboard started');

    await notifications.initialize(
      onNotificationTap: _handleNotificationTap,
      onNotificationAction: _handleNotificationAction,
    );
    notifications.initializeApiService(settings.laptopIp);

    await _checkAndShowWelcomeTour();
  }

  void _handleNotificationTap(String? payload) {
    if (payload == 'file_transfer') {
      context.read<SettingsNotifier>().setDrawerIndex(1);
    }
  }

  void _handleNotificationAction(String action) {
    if (action == 'download') {
      context.read<SettingsNotifier>().setDrawerIndex(1);
    }
  }

  Future<void> _checkAndShowWelcomeTour() async {
    final settings = context.read<SettingsNotifier>();
    if (settings.hasSeenWelcomeTour) return;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WelcomeTourScreen()));
    await settings.setHasSeenWelcomeTour(true);
    context.read<LogsNotifier>().addLog('Welcome tour completed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final settings = context.read<SettingsNotifier>();
      context.read<StatsNotifier>().onAppResumed(
        settings.pollingIntervalSeconds,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsNotifier>(
      builder: (context, settings, _) {
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
          drawer: _buildDrawer(settings),
          body: IndexedStack(
            index: settings.drawerIndex,
            children: const [
              DashboardScreen(),
              FileTransferScreen(),
              SettingsScreen(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer(SettingsNotifier settings) {
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
        context.read<SettingsNotifier>().setDrawerIndex(index);
        Navigator.pop(context);
      },
    );
  }
}
