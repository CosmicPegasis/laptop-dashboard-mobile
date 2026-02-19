import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:path_provider/path_provider.dart';

import 'models/file_info.dart';
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

  String laptopIp = 'localhost';
  final TextEditingController _ipController = TextEditingController(
    text: 'localhost',
  );
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

  // File download state
  List<FileInfo> _availableFiles = [];
  Set<String> _seenFiles = {};
  int _newFileCount = 0;
  bool _isDownloading = false;
  Map<String, double> _fileDownloadProgress = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(laptopIp: laptopIp);
    _initApp();
  }

  Future<void> _initApp() async {
    await _loadSettings();
    await _loadSeenFiles();
    await _notificationService.initialize(
      onNotificationTap: _handleNotificationTap,
      onNotificationAction: _handleNotificationAction,
    );
    await _checkPermissions();
    _startTimer();
    _addLog('Dashboard started');
    _initSharing();
    _checkAndShowWelcomeTour();
  }

  Future<void> _loadSeenFiles() async {
    final seen = await _storageService.getSeenFiles();
    setState(() => _seenFiles = seen);
  }

  void _handleNotificationTap(String? payload) {
    if (payload == 'file_transfer') {
      setState(() => _selectedDrawerIndex = 1);
    }
  }

  void _handleNotificationAction(String action) {
    if (action == 'download') {
      _downloadLatestFile();
    }
  }

  Future<void> _downloadLatestFile() async {
    final newFiles = _availableFiles
        .where((f) => !_seenFiles.contains(f.name))
        .toList();
    if (newFiles.isEmpty) return;

    setState(() => _selectedDrawerIndex = 1);
    final file = newFiles.first;
    await _downloadFile(file);
  }

  void _initSharing() {
    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            if (value.isNotEmpty) {
              _handleSharedFiles(value);
            }
          },
          onError: (err) {
            _addLog("getIntentDataStream error: $err");
          },
        );

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    _addLog('Received ${files.length} shared file(s)');

    // Switch to File Transfer tab if not already there
    if (_selectedDrawerIndex != 1) {
      setState(() => _selectedDrawerIndex = 1);
    }

    for (final file in files) {
      final filePath = file.path;
      // Extract filename from path
      final fileName = filePath.split('/').last;

      _addLog('Shared upload: $fileName');

      setState(() {
        _pickedFileName = fileName;
        _isUploading = true;
        _uploadProgress = 0.0;
        _uploadStatusMessage = 'Uploading shared: $fileName';
        _uploadSuccess = false;
      });

      try {
        await _apiService.uploadFile(
          filePath: filePath,
          fileName: fileName,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
        setState(() {
          _uploadProgress = 1.0;
          _uploadStatusMessage = 'Shared upload successful: $fileName';
          _uploadSuccess = true;
        });
        _addLog('Uploaded shared: $fileName');

        // Brief delay before starting next file if there are many
        if (files.length > 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        setState(() {
          _uploadStatusMessage = 'Upload error: $e';
          _uploadSuccess = false;
        });
        _addLog('Upload error: $e');
        break; // Stop on first error for batch
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
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
    _notificationPermissionGranted = await _notificationService
        .isPermissionGranted();
    _reverseSyncPermissionGranted = await _reverseSyncService
        .isNotificationAccessEnabled();

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

      // Log all available files for download
      // if (files.isEmpty) {
      //   _addLog('No files available for download');
      // } else {
      //   final fileNames = files.map((f) => f.name).join(', ');
      //   _addLog('Files available for download: $fileNames');
      // }

      // Calculate new files
      final newFiles = files
          .where((f) => !_availableFiles.any((af) => af.name == f.name))
          .toList();

      if (newFiles.isNotEmpty) {
        final newFileNames = newFiles.map((f) => f.name).toSet();
        _addLog('New files available: ${newFileNames.join(', ')}');

        // Show notification for new files
        await _notificationService.showNewFileNotification(
          filename: newFiles.first.name,
          newFileCount: newFiles.length,
          onDownload: () {},
        );
      }

      setState(() {
        _availableFiles = files;
        _newFileCount = _calculateNewFileCount();
      });
    } catch (e) {
      // Silently fail - file fetching is secondary
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

  void _startReverseSync() {
    _reverseSyncService.startListening(
      onEvent: (event) => _apiService
          .forwardNotification(event)
          .then((_) {
            final title = event['title']?.toString();
            final packageName =
                event['package_name']?.toString() ?? 'unknown_app';
            _addLog('Forwarded phone notification: ${title ?? packageName}');
          })
          .catchError((e) {
            _addLog('Reverse sync error: $e');
            return null;
          }),
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

  Future<void> _downloadFile(FileInfo file) async {
    setState(() {
      _isDownloading = true;
      _fileDownloadProgress[file.name] = 0.0;
    });
    _addLog('Downloading: ${file.name}');

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not access Downloads folder');
      }

      final savePath = '${downloadsDir.path}/${file.name}';

      await _apiService.downloadFile(
        filename: file.name,
        savePath: savePath,
        onProgress: (p) => setState(() => _fileDownloadProgress[file.name] = p),
      );

      await _storageService.markFileAsSeen(file.name);
      setState(() {
        _seenFiles.add(file.name);
        _newFileCount = _calculateNewFileCount();
        _fileDownloadProgress[file.name] = 1.0;
      });
      _addLog('Downloaded: ${file.name}');
    } catch (e) {
      _addLog('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  int _calculateNewFileCount() {
    return _availableFiles.where((f) => !_seenFiles.contains(f.name)).length;
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
      body: _buildBody(),
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
    final bool showBadge = index == 1 && _newFileCount > 0;
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon),
          if (showBadge)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  '$_newFileCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(title),
      selected: _selectedDrawerIndex == index,
      onTap: () {
        if (index == 1) {
          // Mark all files as seen when opening File Transfer
          for (final file in _availableFiles) {
            if (!_seenFiles.contains(file.name)) {
              _storageService.markFileAsSeen(file.name);
            }
          }
          setState(() {
            _seenFiles = Set.from(_availableFiles.map((f) => f.name));
            _newFileCount = 0;
          });
        }
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
        availableFiles: _availableFiles,
        seenFiles: _seenFiles,
        isDownloading: _isDownloading,
        fileDownloadProgress: _fileDownloadProgress,
        onDownloadFile: _downloadFile,
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
        onOpenReverseSyncSettings:
            _reverseSyncService.openNotificationAccessSettings,
        onRequestNotificationPermission: () => _notificationService
            .checkAndRequestPermission()
            .then((v) => setState(() => _notificationPermissionGranted = v)),
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
        onRequestNotificationPermission: () => _notificationService
            .checkAndRequestPermission()
            .then((v) => setState(() => _notificationPermissionGranted = v)),
      ),
    };
  }
}
