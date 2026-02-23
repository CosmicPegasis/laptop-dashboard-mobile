import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'services/storage_service.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/reverse_sync_service.dart';
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  static const int _offlineNotificationId = 1;

  final StorageService _storageService = StorageService();
  final NotificationService _notificationService = NotificationService();
  final ReverseSyncService _reverseSyncService = ReverseSyncService();
  late ApiService _apiService;
  StreamSubscription? _intentDataStreamSubscription;

  // Key used to call methods on FileTransferScreen's state
  final GlobalKey<FileTransferScreenState> _fileTransferKey = GlobalKey();

  String laptopIp = 'localhost';
  final TextEditingController _ipController = TextEditingController(
    text: 'localhost',
  );
  Timer? _timer;
  int _pollingIntervalSeconds = 2;
  static const int _minPollingIntervalSeconds = 1;
  static const int _maxPollingIntervalSeconds = 30;

  // Stats (Dashboard)
  double cpu = 0.0;
  double ram = 0.0;
  double temp = 0.0;
  double battery = 0.0;
  bool isPlugged = false;

  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  int _fetchCount = 0;
  bool _isSleeping = false;
  bool _isFetchingStats = false;
  int _selectedDrawerIndex = 0;
  bool _offlineNotificationShown = false;
  int _consecutiveFailures = 0;
  static const int _maxFailuresBeforeOffline = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(laptopIp: laptopIp);
    _initApp();
  }

  Future<void> _initApp() async {
    await _loadSettings();
    await _notificationService.initialize(
      onNotificationTap: _handleNotificationTap,
      onNotificationAction: _handleNotificationAction,
    );
    _startTimer();
    _addLog('Dashboard started');
    _initSharing();
    _checkAndShowWelcomeTour();
  }

  void _handleNotificationTap(String? payload) {
    if (payload == 'file_transfer') {
      setState(() => _selectedDrawerIndex = 1);
    }
  }

  void _handleNotificationAction(String action) {
    if (action == 'download') {
      setState(() => _selectedDrawerIndex = 1);
    }
  }

  void _initSharing() {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            if (value.isNotEmpty) _handleSharedFiles(value);
          },
          onError: (err) => _addLog('getIntentDataStream error: $err'),
        );

    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) _handleSharedFiles(value);
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    _addLog('Received ${files.length} shared file(s)');
    if (_selectedDrawerIndex != 1) setState(() => _selectedDrawerIndex = 1);

    final mapped = files
        .map((f) => (path: f.path, name: f.path.split('/').last))
        .toList();

    for (final f in mapped) {
      _addLog('Shared upload: ${f.name}');
    }

    // Delegate to FileTransferScreen — it owns upload state
    await _fileTransferKey.currentState?.uploadSharedFiles(mapped);
  }

  Future<void> _loadSettings() async {
    laptopIp = await _storageService.getLaptopIp();
    _pollingIntervalSeconds = await _storageService.getPollingInterval();

    if (mounted) {
      setState(() {
        _ipController.text = laptopIp;
        _apiService = ApiService(laptopIp: laptopIp);
      });
    }
  }

  Future<void> _checkAndShowWelcomeTour() async {
    if (await _storageService.getHasSeenWelcomeTour()) return;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WelcomeTourScreen()));
    await _storageService.saveHasSeenWelcomeTour(true);
    _addLog('Welcome tour completed');
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _pollingIntervalSeconds),
      (_) => _fetchAll(),
    );
  }

  Future<void> _fetchAll() async {
    await Future.wait([_fetchStats(), _fetchFiles()]);
  }

  Future<void> _fetchStats() async {
    if (_isFetchingStats) return;
    _isFetchingStats = true;
    try {
      final stats = await _apiService.fetchStats();

      bool valuesChanged =
          stats.cpu != cpu ||
          stats.ram != ram ||
          stats.temp != temp ||
          stats.battery != battery ||
          stats.isPlugged != isPlugged;

      if (!mounted) return;
      setState(() {
        cpu = stats.cpu;
        ram = stats.ram;
        temp = stats.temp;
        battery = stats.battery;
        isPlugged = stats.isPlugged;
      });

      await _markOnline();
      _notificationService.updateForegroundService(
        cpu: cpu,
        ram: ram,
        temp: temp,
        battery: battery,
        isPlugged: isPlugged,
      );

      _fetchCount++;
      if (valuesChanged || _fetchCount % 5 == 0) {
        _addLog(
          'Stats updated (${valuesChanged ? 'values changed' : 'periodic sync'})',
        );
      }
    } catch (e) {
      await _markOffline(
        'Connection failed: ${e.toString().split('\n').first}',
      );
    } finally {
      _isFetchingStats = false;
    }
  }

  Future<void> _fetchFiles() async {
    try {
      final files = await _apiService.listFiles();
      _fileTransferKey.currentState?.updateAvailableFiles(files);
    } catch (e) {
      // Silently fail — file fetching is secondary
    }
  }

  Future<void> _markOffline(String reason) async {
    _consecutiveFailures++;
    if (_consecutiveFailures < _maxFailuresBeforeOffline) {
      _addLog(
        'Sync attempt failed ($_consecutiveFailures/$_maxFailuresBeforeOffline): $reason',
      );
      return;
    }
    if (!_offlineNotificationShown) {
      _offlineNotificationShown = true;
      await _notificationService.showOfflineNotification(
        _offlineNotificationId,
        laptopIp,
      );
      _addLog(reason);
    }
  }

  Future<void> _markOnline() async {
    _consecutiveFailures = 0;
    if (!_offlineNotificationShown) return;
    _offlineNotificationShown = false;
    await _notificationService.cancelNotification(_offlineNotificationId);
    _addLog('Connection restored to $laptopIp');
  }

  void _addLog(String message) {
    if (!mounted) return;
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _logs.add('[$timestamp] $message');
      if (_logs.length > 100) _logs.removeAt(0);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _updateIp(String value) {
    final newIp = value.trim().isEmpty ? 'localhost' : value.trim();
    if (newIp == laptopIp) return;
    setState(() {
      laptopIp = newIp;
      _apiService = ApiService(laptopIp: laptopIp);
    });
    _storageService.saveLaptopIp(newIp);
    _addLog('IP changed to $laptopIp');
  }

  void _setPollingInterval(int seconds) {
    final normalized = seconds.clamp(
      _minPollingIntervalSeconds,
      _maxPollingIntervalSeconds,
    );
    if (normalized == _pollingIntervalSeconds) return;
    setState(() => _pollingIntervalSeconds = normalized);
    _storageService.savePollingInterval(normalized);
    _startTimer();
    _addLog('Polling interval changed to ${normalized}s');
  }

  void _showSleepConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sleep Laptop?'),
        content: const Text(
          'Are you sure you want to put your laptop to sleep?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sleepLaptop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Sleep', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _sleepLaptop() async {
    setState(() => _isSleeping = true);
    try {
      await _apiService.sleepLaptop();
      _addLog('Success: Laptop putting to sleep');
    } catch (e) {
      _addLog('Sleep failed: $e');
    } finally {
      if (mounted) setState(() => _isSleeping = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _intentDataStreamSubscription?.cancel();
    _reverseSyncService.stopListening();
    _ipController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = switch (_selectedDrawerIndex) {
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
        index: _selectedDrawerIndex,
        children: [
          DashboardScreen(
            cpu: cpu,
            ram: ram,
            temp: temp,
            battery: battery,
            isPlugged: isPlugged,
            logs: _logs,
            scrollController: _scrollController,
            isSleeping: _isSleeping,
            onSleepPressed: _showSleepConfirmation,
          ),
          FileTransferScreen(
            key: _fileTransferKey,
            laptopIp: laptopIp,
            apiService: _apiService,
            storageService: _storageService,
            notificationService: _notificationService,
          ),
          SettingsScreen(
            ipController: _ipController,
            laptopIp: laptopIp,
            pollingIntervalSeconds: _pollingIntervalSeconds,
            minPollingInterval: _minPollingIntervalSeconds,
            maxPollingInterval: _maxPollingIntervalSeconds,
            storageService: _storageService,
            notificationService: _notificationService,
            reverseSyncService: _reverseSyncService,
            onIpChanged: _updateIp,
            onPollingIntervalChanged: _setPollingInterval,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
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
          _drawerTile(0, Icons.dashboard, 'Dashboard'),
          _drawerTile(1, Icons.upload_file, 'File Transfer'),
          _drawerTile(2, Icons.settings, 'Settings'),
        ],
      ),
    );
  }

  Widget _drawerTile(int index, IconData icon, String title) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: _selectedDrawerIndex == index,
      onTap: () {
        setState(() => _selectedDrawerIndex = index);
        Navigator.pop(context);
      },
    );
  }
}
