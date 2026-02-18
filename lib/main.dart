import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

import 'models/app_stats.dart';
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

  String laptopIp = 'localhost';
  final TextEditingController _ipController = TextEditingController(text: 'localhost');
  Timer? _timer;
  int _pollingIntervalSeconds = 2;
  static const int _minPollingIntervalSeconds = 1;
  static const int _maxPollingIntervalSeconds = 30;

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

  bool _notificationPermissionGranted = false;
  bool _notificationPermissionChecked = false;
  bool _reverseSyncEnabled = false;
  bool _reverseSyncPermissionGranted = false;
  bool _reverseSyncPermissionChecked = false;

  // File transfer state
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _uploadStatusMessage;
  String? _pickedFileName;
  bool _uploadSuccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(laptopIp: laptopIp);
    _initApp();
  }

  Future<void> _initApp() async {
    await _loadSettings();
    await _notificationService.initialize();
    await _checkPermissions();
    _startTimer();
    _addLog('Dashboard started');
    _checkAndShowWelcomeTour();
  }

  Future<void> _loadSettings() async {
    laptopIp = await _storageService.getLaptopIp();
    _pollingIntervalSeconds = await _storageService.getPollingInterval();
    _reverseSyncEnabled = await _storageService.getReverseSyncEnabled();
    
    if (mounted) {
      setState(() {
        _ipController.text = laptopIp;
        _apiService = ApiService(laptopIp: laptopIp);
      });
    }
  }

  Future<void> _checkPermissions() async {
    _notificationPermissionGranted = await _notificationService.isPermissionGranted();
    _reverseSyncPermissionGranted = await _reverseSyncService.isNotificationAccessEnabled();
    
    if (mounted) {
      setState(() {
        _notificationPermissionChecked = true;
        _reverseSyncPermissionChecked = true;
      });
    }
    
    if (_reverseSyncEnabled && _reverseSyncPermissionGranted) {
      _startReverseSync();
    }
  }

  Future<void> _checkAndShowWelcomeTour() async {
    if (await _storageService.getHasSeenWelcomeTour()) return;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WelcomeTourScreen()),
    );
    await _storageService.saveHasSeenWelcomeTour(true);
    _addLog('Welcome tour completed');
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _pollingIntervalSeconds), (_) => _fetchStats());
  }

  Future<void> _fetchStats() async {
    if (_isFetchingStats) return;
    _isFetchingStats = true;
    try {
      final stats = await _apiService.fetchStats();
      
      bool valuesChanged = stats.cpu != cpu ||
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
        _addLog('Stats updated (${valuesChanged ? 'values changed' : 'periodic sync'})');
      }
    } catch (e) {
      await _markOffline('Connection failed: ${e.toString().split('\n').first}');
    } finally {
      _isFetchingStats = false;
    }
  }

  Future<void> _markOffline(String reason) async {
    _consecutiveFailures++;
    if (_consecutiveFailures < _maxFailuresBeforeOffline) {
      _addLog('Sync attempt failed ($_consecutiveFailures/$_maxFailuresBeforeOffline): $reason');
      return;
    }
    if (!_offlineNotificationShown) {
      _offlineNotificationShown = true;
      await _notificationService.showOfflineNotification(_offlineNotificationId, laptopIp);
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

  void _startReverseSync() {
    _reverseSyncService.startListening(
      onEvent: (event) => _apiService.forwardNotification(event).then((_) {
        final title = event['title']?.toString();
        final packageName = event['package_name']?.toString() ?? 'unknown_app';
        _addLog('Forwarded phone notification: ${title ?? packageName}');
      }).catchError((e) => _addLog('Reverse sync error: $e')),
      onError: (error) => _addLog('Reverse sync stream error: $error'),
    );
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
    final normalized = seconds.clamp(_minPollingIntervalSeconds, _maxPollingIntervalSeconds);
    if (normalized == _pollingIntervalSeconds) return;
    setState(() => _pollingIntervalSeconds = normalized);
    _storageService.savePollingInterval(normalized);
    _startTimer();
    _addLog('Polling interval changed to ${normalized}s');
  }

  Future<void> _setReverseSyncEnabled(bool enabled) async {
    if (!_reverseSyncService.isSupported) {
      _addLog('Reverse sync requires Android');
      return;
    }
    setState(() => _reverseSyncEnabled = enabled);
    await _storageService.saveReverseSyncEnabled(enabled);

    if (enabled) {
      _addLog('Reverse sync enabled');
      _checkPermissions();
    } else {
      _addLog('Reverse sync disabled');
      _reverseSyncService.stopListening();
    }
  }

  void _showSleepConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sleep Laptop?'),
        content: const Text('Are you sure you want to put your laptop to sleep?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final filePath = file.path;
    if (filePath == null) return;

    setState(() {
      _pickedFileName = file.name;
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadStatusMessage = null;
      _uploadSuccess = false;
    });
    _addLog('Uploading: ${file.name}');

    try {
      await _apiService.uploadFile(
        filePath: filePath,
        fileName: file.name,
        onProgress: (p) => setState(() => _uploadProgress = p),
      );
      setState(() {
        _uploadProgress = 1.0;
        _uploadStatusMessage = 'Upload successful!';
        _uploadSuccess = true;
      });
      _addLog('Uploaded: ${file.name}');
    } catch (e) {
      setState(() {
        _uploadStatusMessage = 'Upload error: $e';
        _uploadSuccess = false;
      });
      _addLog('Upload error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _startTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
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
      body: _buildBody(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: const Align(
              alignment: Alignment.bottomLeft,
              child: Text('Laptop Dashboard', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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

  Widget _buildBody() {
    return switch (_selectedDrawerIndex) {
      1 => FileTransferScreen(
          laptopIp: laptopIp,
          isUploading: _isUploading,
          uploadProgress: _uploadProgress,
          uploadStatusMessage: _uploadStatusMessage,
          pickedFileName: _pickedFileName,
          uploadSuccess: _uploadSuccess,
          onPickAndUploadFile: _pickAndUploadFile,
        ),
      2 => SettingsScreen(
          ipController: _ipController,
          laptopIp: laptopIp,
          pollingIntervalSeconds: _pollingIntervalSeconds,
          minPollingInterval: _minPollingIntervalSeconds,
          maxPollingInterval: _maxPollingIntervalSeconds,
          reverseSyncEnabled: _reverseSyncEnabled,
          reverseSyncPermissionChecked: _reverseSyncPermissionChecked,
          reverseSyncPermissionGranted: _reverseSyncPermissionGranted,
          supportsReverseSync: _reverseSyncService.isSupported,
          notificationPermissionChecked: _notificationPermissionChecked,
          notificationPermissionGranted: _notificationPermissionGranted,
          onIpChanged: _updateIp,
          onPollingIntervalChanged: _setPollingInterval,
          onReverseSyncChanged: _setReverseSyncEnabled,
          onOpenReverseSyncSettings: _reverseSyncService.openNotificationAccessSettings,
          onRequestNotificationPermission: () => _notificationService.checkAndRequestPermission().then((v) => setState(() => _notificationPermissionGranted = v)),
        ),
      _ => DashboardScreen(
          cpu: cpu,
          ram: ram,
          temp: temp,
          battery: battery,
          isPlugged: isPlugged,
          logs: _logs,
          scrollController: _scrollController,
          isSleeping: _isSleeping,
          notificationPermissionChecked: _notificationPermissionChecked,
          notificationPermissionGranted: _notificationPermissionGranted,
          onSleepPressed: _showSleepConfirmation,
          onRequestNotificationPermission: () => _notificationService.checkAndRequestPermission().then((v) => setState(() => _notificationPermissionGranted = v)),
        ),
    };
  }
}
