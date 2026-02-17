import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const int _persistentNotificationId = 0;
  static const int _offlineNotificationId = 1;
  static const EventChannel _phoneNotificationEventChannel = EventChannel(
    'laptop_dashboard_mobile/notification_events',
  );
  static const MethodChannel _phoneNotificationMethodChannel = MethodChannel(
    'laptop_dashboard_mobile/notification_sync_control',
  );

  String laptopIp = 'localhost';
  final TextEditingController _ipController = TextEditingController(
    text: 'localhost',
  );
  Timer? _timer;
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
  bool _notificationPermissionGranted = false;
  bool _notificationPermissionChecked = false;
  bool _reverseSyncEnabled = false;
  bool _reverseSyncPermissionGranted = false;
  bool _reverseSyncPermissionChecked = false;
  StreamSubscription<dynamic>? _phoneNotificationSubscription;
  String _lastForwardedNotificationKey = '';

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _notificationInitFuture;
  bool _notificationPluginInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLaptopIp();
    _loadReverseSyncPreference();
    _checkAndShowWelcomeTour();
    _notificationInitFuture = _initializeNotifications();
    unawaited(_bootstrapNotificationPermission());
    _refreshReverseSyncPermissionStatus();
    _startTimer();
    _addLog('Dashboard started');
  }

  Future<void> _bootstrapNotificationPermission() async {
    await _ensureNotificationsInitialized();
    await _checkAndRequestNotificationPermission();
  }

  Future<void> _checkAndShowWelcomeTour() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTour = prefs.getBool('has_seen_welcome_tour') ?? false;
    if (hasSeenTour || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const WelcomeTourScreen()),
      );
      if (!mounted) return;
      await prefs.setBool('has_seen_welcome_tour', true);
      _addLog('Welcome tour completed');
    });
  }

  Future<void> _loadLaptopIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('laptop_ip') ?? 'localhost';
    setState(() {
      laptopIp = savedIp;
      _ipController.text = savedIp;
    });
    _addLog('Loaded IP: $savedIp');
  }

  Future<void> _saveLaptopIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('laptop_ip', ip);
  }

  void _updateLaptopIp(String value) {
    final newIp = value.trim().isEmpty ? 'localhost' : value.trim();
    if (newIp == laptopIp) return;
    setState(() {
      laptopIp = newIp;
    });
    _saveLaptopIp(newIp);
    _addLog('IP changed to $laptopIp');
  }

  bool get _supportsReverseSync => Platform.isAndroid;

  Future<void> _loadReverseSyncPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEnabled = prefs.getBool('reverse_sync_enabled') ?? false;
    if (!mounted) return;
    setState(() {
      _reverseSyncEnabled = savedEnabled;
    });
    if (savedEnabled) {
      _addLog('Reverse sync enabled');
      _startPhoneNotificationListenerIfReady();
    }
  }

  Future<void> _saveReverseSyncPreference(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reverse_sync_enabled', enabled);
  }

  Future<void> _setReverseSyncEnabled(bool enabled) async {
    if (!_supportsReverseSync) {
      _addLog('Reverse sync requires Android');
      return;
    }

    if (!mounted) return;
    setState(() {
      _reverseSyncEnabled = enabled;
    });
    await _saveReverseSyncPreference(enabled);

    if (enabled) {
      _addLog('Reverse sync enabled');
      await _refreshReverseSyncPermissionStatus();
      _startPhoneNotificationListenerIfReady();
      return;
    }

    _addLog('Reverse sync disabled');
    await _phoneNotificationSubscription?.cancel();
    _phoneNotificationSubscription = null;
  }

  Future<void> _refreshReverseSyncPermissionStatus() async {
    if (!_supportsReverseSync) {
      if (!mounted) return;
      setState(() {
        _reverseSyncPermissionGranted = false;
        _reverseSyncPermissionChecked = true;
      });
      return;
    }

    try {
      final enabled =
          await _phoneNotificationMethodChannel.invokeMethod<bool>(
            'isNotificationAccessEnabled',
          ) ??
          false;
      if (!mounted) return;
      setState(() {
        _reverseSyncPermissionGranted = enabled;
        _reverseSyncPermissionChecked = true;
      });
      if (!enabled) {
        await _phoneNotificationSubscription?.cancel();
        _phoneNotificationSubscription = null;
      }
      _startPhoneNotificationListenerIfReady();
    } catch (e) {
      _addLog('Could not verify reverse sync permission: $e');
      if (!mounted) return;
      setState(() {
        _reverseSyncPermissionGranted = false;
        _reverseSyncPermissionChecked = true;
      });
    }
  }

  Future<void> _openReverseSyncSettings() async {
    if (!_supportsReverseSync) return;
    try {
      await _phoneNotificationMethodChannel.invokeMethod(
        'openNotificationAccessSettings',
      );
      _addLog('Opened Android notification access settings');
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        _refreshReverseSyncPermissionStatus();
      });
    } catch (e) {
      _addLog('Could not open notification access settings: $e');
    }
  }

  void _startPhoneNotificationListenerIfReady() {
    if (!_supportsReverseSync) return;
    if (!_reverseSyncEnabled || !_reverseSyncPermissionGranted) return;
    if (_phoneNotificationSubscription != null) return;

    _phoneNotificationSubscription = _phoneNotificationEventChannel
        .receiveBroadcastStream()
        .listen(
          _handlePhoneNotificationEvent,
          onError: (Object error) {
            _addLog('Reverse sync stream error: $error');
          },
        );

    _addLog('Reverse sync listener started');
  }

  Future<void> _handlePhoneNotificationEvent(dynamic event) async {
    if (!_reverseSyncEnabled || !_reverseSyncPermissionGranted) return;
    if (event is! Map) return;

    final map = Map<String, dynamic>.from(event);
    final packageName = map['package_name']?.toString() ?? 'unknown_app';
    final title = map['title']?.toString() ?? '';
    final text = map['text']?.toString() ?? '';
    final postedAt = map['posted_at'];
    final isOngoing = _toBool(map['is_ongoing']);

    if (title.isEmpty && text.isEmpty) return;
    if (isOngoing) return;

    final key = '$packageName|$title|$text|$postedAt';
    if (key == _lastForwardedNotificationKey) return;
    _lastForwardedNotificationKey = key;

    final payload = <String, dynamic>{
      'package_name': packageName,
      'title': title,
      'text': text,
      'posted_at': postedAt,
    };

    await _forwardPhoneNotificationToLaptop(payload);
  }

  Future<void> _forwardPhoneNotificationToLaptop(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://$laptopIp:8081/phone-notification'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final title = payload['title']?.toString();
        final packageName =
            payload['package_name']?.toString() ?? 'unknown_app';
        final label = (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : packageName;
        _addLog('Forwarded phone notification: $label');
      } else {
        _addLog('Reverse sync failed (${response.statusCode})');
      }
    } on TimeoutException {
      _addLog('Reverse sync timeout to $laptopIp');
    } catch (e) {
      _addLog('Reverse sync error: ${e.toString().split('\n').first}');
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    try {
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);
      _notificationPluginInitialized = true;
    } on PlatformException catch (e) {
      _notificationPluginInitialized = false;
      _addLog(
        'Notification initialization failed: ${e.code}'
        '${e.message == null ? '' : ' (${e.message})'}',
      );
    } catch (e) {
      _notificationPluginInitialized = false;
      _addLog(
        'Notification initialization failed: ${e.toString().split('\n').first}',
      );
    }
  }

  Future<void> _ensureNotificationsInitialized() async {
    if (_notificationPluginInitialized) {
      return;
    }
    _notificationInitFuture ??= _initializeNotifications();
    await _notificationInitFuture;
  }

  bool get _supportsNotificationPermission =>
      Platform.isAndroid || Platform.isIOS;

  Future<void> _refreshNotificationPermissionStatus() async {
    final status = await _resolveNotificationPermissionStatus();
    if (!mounted) return;
    setState(() {
      _notificationPermissionGranted = status;
      _notificationPermissionChecked = true;
    });

    if (status && !_offlineNotificationShown) {
      await _showPersistentNotification();
    }
  }

  Future<void> _checkAndRequestNotificationPermission() async {
    if (!_supportsNotificationPermission) {
      if (mounted) {
        setState(() {
          _notificationPermissionGranted = true;
          _notificationPermissionChecked = true;
        });
      }
      return;
    }

    final currentStatus = await _resolveNotificationPermissionStatus();
    if (currentStatus) {
      if (!mounted) return;
      setState(() {
        _notificationPermissionGranted = true;
        _notificationPermissionChecked = true;
      });
      _addLog('Notifications permission granted');
      return;
    }

    final requestedStatus = await Permission.notification.request();
    final isGranted =
        requestedStatus.isGranted ||
        await _resolveNotificationPermissionStatus();
    if (!mounted) return;
    setState(() {
      _notificationPermissionGranted = isGranted;
      _notificationPermissionChecked = true;
    });

    if (isGranted) {
      _addLog('Notifications permission granted');
      if (!_offlineNotificationShown) {
        await _showPersistentNotification();
      }
      return;
    }

    if (requestedStatus.isPermanentlyDenied) {
      _addLog('Notifications permission permanently denied');
      return;
    }

    _addLog('Notifications permission denied');
  }

  Future<void> _requestNotificationPermissionFromSettings() async {
    await _checkAndRequestNotificationPermission();
    if (_notificationPermissionGranted) return;

    final status = await Permission.notification.status;
    if (!mounted || !status.isPermanentlyDenied) return;
    await openAppSettings();
  }

  Future<void> _showPersistentNotification() async {
    if (!await _resolveNotificationPermissionStatus()) return;
    final String plugStatus = isPlugged ? 'Charging' : 'Discharging';
    final AndroidNotificationDetails
    androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'laptop_stats_channel',
      'Laptop Stats',
      channelDescription: 'Persistent notification for laptop statistics',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      onlyAlertOnce: true,
      styleInformation: BigTextStyleInformation(
        'CPU: ${cpu.toStringAsFixed(1)}% | RAM: ${ram.toStringAsFixed(1)}%\n'
        'Temp: ${temp.toStringAsFixed(1)}°C | Battery: ${battery.toStringAsFixed(0)}% ($plugStatus)',
      ),
    );
    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await _showNotificationSafely(
      _persistentNotificationId,
      'Laptop Status: ${battery.toStringAsFixed(0)}% ($plugStatus)',
      'CPU: ${cpu.toStringAsFixed(1)}% | RAM: ${ram.toStringAsFixed(1)}%',
      platformChannelSpecifics,
    );
  }

  Future<void> _showOfflineNotification() async {
    if (!await _resolveNotificationPermissionStatus()) return;
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'laptop_offline_channel',
          'Laptop Offline',
          channelDescription: 'Notification when laptop connection is offline',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: true,
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await _showNotificationSafely(
      _offlineNotificationId,
      'Laptop Offline',
      'Cannot reach $laptopIp. We will notify again after it reconnects and goes offline later.',
      platformChannelSpecifics,
    );
  }

  Future<void> _showNotificationSafely(
    int id,
    String title,
    String body,
    NotificationDetails details,
  ) async {
    await _ensureNotificationsInitialized();
    try {
      await flutterLocalNotificationsPlugin.show(id, title, body, details);
    } on PlatformException catch (e) {
      _addLog(
        'Notification show failed: ${e.code}'
        '${e.message == null ? '' : ' (${e.message})'}',
      );
    } catch (e) {
      _addLog('Notification show failed: ${e.toString().split('\n').first}');
    }
  }

  Future<void> _clearOfflineNotification() async {
    await flutterLocalNotificationsPlugin.cancel(_offlineNotificationId);
  }

  Future<void> _markOffline(String reason) async {
    if (_offlineNotificationShown) return;
    _offlineNotificationShown = true;
    await _showOfflineNotification();
    _addLog(reason);
  }

  Future<void> _markOnline() async {
    if (!_offlineNotificationShown) return;
    _offlineNotificationShown = false;
    await _clearOfflineNotification();
    _addLog('Connection restored to $laptopIp');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _addLog('App State: ${state.name}');
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationPermissionStatus();
      _refreshReverseSyncPermissionStatus();
      _startTimer();
    } else if (state == AppLifecycleState.paused) {
      // Keep timer running in background if we want persistent updates
      // _timer?.cancel();
    }
  }

  void _addLog(String message) {
    if (!mounted) return;
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _logs.add('[$timestamp] $message');
      if (_logs.length > 100) _logs.removeAt(0);
    });

    // Auto-scroll to bottom
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

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchStats();
    });
  }

  Future<void> _fetchStats() async {
    if (_isFetchingStats) return;
    _isFetchingStats = true;
    try {
      final response = await http
          .get(Uri.parse('http://$laptopIp:8081/stats'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is! Map<String, dynamic>) {
          await _markOffline('Invalid stats payload: expected JSON object');
          return;
        }

        final newCpu = _toDouble(decoded['cpu_usage']);
        final newRam = _toDouble(decoded['ram_usage']);
        final newTemp = _toDouble(decoded['cpu_temp']);
        final newBattery = _toDouble(decoded['battery_percent']);
        final newPlugged = _toBool(decoded['is_plugged']);

        bool valuesChanged =
            newCpu != cpu ||
            newRam != ram ||
            newTemp != temp ||
            newBattery != battery ||
            newPlugged != isPlugged;

        if (!mounted) return;
        setState(() {
          cpu = newCpu;
          ram = newRam;
          temp = newTemp;
          battery = newBattery;
          isPlugged = newPlugged;
        });

        await _markOnline();
        await _showPersistentNotification();

        _fetchCount++;
        if (valuesChanged || _fetchCount % 5 == 0) {
          String reason = valuesChanged ? 'values changed' : 'periodic sync';
          _addLog('Stats updated ($reason)');
        }
      } else {
        await _markOffline('Error: Server returned ${response.statusCode}');
      }
    } on TimeoutException {
      await _markOffline('Connection timeout to $laptopIp');
    } catch (e) {
      await _markOffline(
        'Connection failed: ${e.toString().split('\n').first}',
      );
      debugPrint('Error fetching stats: $e');
    } finally {
      _isFetchingStats = false;
    }
  }

  double _toDouble(Object? value) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0.0;
    }

    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed.isFinite) {
        return parsed;
      }
    }

    return 0.0;
  }

  bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return false;
  }

  Future<bool> _resolveNotificationPermissionStatus() async {
    if (!_supportsNotificationPermission) {
      return true;
    }

    await _ensureNotificationsInitialized();

    if (Platform.isAndroid) {
      try {
        final androidImplementation = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidImplementation != null) {
          final enabled =
              await androidImplementation.areNotificationsEnabled() ?? false;
          if (mounted && enabled != _notificationPermissionGranted) {
            setState(() {
              _notificationPermissionGranted = enabled;
              _notificationPermissionChecked = true;
            });
          }
          return enabled;
        }
      } on PlatformException catch (e) {
        _addLog(
          'areNotificationsEnabled failed: ${e.code}'
          '${e.message == null ? '' : ' (${e.message})'}',
        );
      } catch (e) {
        _addLog(
          'areNotificationsEnabled failed: ${e.toString().split('\n').first}',
        );
      }
    }

    final status = await Permission.notification.status;
    final granted = status.isGranted;
    if (mounted && granted != _notificationPermissionGranted) {
      setState(() {
        _notificationPermissionGranted = granted;
        _notificationPermissionChecked = true;
      });
    }
    return granted;
  }

  Future<void> _sleepLaptop() async {
    setState(() => _isSleeping = true);
    try {
      final response = await http
          .post(Uri.parse('http://$laptopIp:8081/sleep'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        _addLog('Success: Laptop putting to sleep');
      } else {
        _addLog('Error: Could not sleep laptop (${response.statusCode})');
      }
    } on TimeoutException {
      _addLog('Sleep request timed out (it might be sleeping now!)');
    } catch (e) {
      _addLog('Sleep failed: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _isSleeping = false);
    }
  }

  void _showSleepConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sleep Laptop?'),
        content: const Text(
          'Are you sure you want to put your laptop to sleep? You will lose connection until it wakes up.',
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _phoneNotificationSubscription?.cancel();
    _ipController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSettingsPage = _selectedDrawerIndex == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(isSettingsPage ? 'Settings' : 'Laptop Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      drawer: Drawer(
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
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              selected: _selectedDrawerIndex == 0,
              onTap: () {
                setState(() => _selectedDrawerIndex = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              selected: _selectedDrawerIndex == 1,
              onTap: () {
                setState(() => _selectedDrawerIndex = 1);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: isSettingsPage
          ? _buildSettingsPage()
          : _buildDashboardPage(context),
    );
  }

  Widget _buildDashboardPage(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_notificationPermissionChecked &&
                !_notificationPermissionGranted)
              _buildNotificationPermissionCard(),
            const SizedBox(height: 20),
            const Text(
              'Hello, Aviral!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SStatusCard(
              cpu: cpu,
              ram: ram,
              temp: temp,
              battery: battery,
              isPlugged: isPlugged,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _isSleeping
                      ? null
                      : () => _showSleepConfirmation(context),
                  icon: _isSleeping
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new),
                  label: Text(_isSleeping ? 'Suspending...' : 'Sleep Laptop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade100,
                    foregroundColor: Colors.orange.shade900,
                  ),
                ),
              ),
            ),
            LogCard(logs: _logs, scrollController: _scrollController),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPage() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_notificationPermissionChecked &&
                !_notificationPermissionGranted) ...[
              _buildNotificationPermissionCard(),
              const SizedBox(height: 12),
            ],
            const Text(
              'Connection Settings',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Set the laptop IP or hostname used for daemon requests.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Laptop IP',
                hintText: 'e.g. 192.168.1.10',
                border: OutlineInputBorder(),
              ),
              onChanged: _updateLaptopIp,
            ),
            const SizedBox(height: 10),
            Text(
              'Current target: $laptopIp:8081',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const Text(
              'Reverse Sync',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildReverseSyncCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationPermissionCard() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications are disabled',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enable notifications to keep live laptop status updates in the notification tray.',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: _requestNotificationPermissionFromSettings,
                child: const Text('Enable notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReverseSyncCard() {
    if (!_supportsReverseSync) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('Reverse sync is currently supported on Android only.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Forward phone notifications to laptop'),
              subtitle: const Text(
                'Pushes Android notifications to the daemon endpoint at /phone-notification.',
              ),
              value: _reverseSyncEnabled,
              onChanged: _setReverseSyncEnabled,
            ),
            if (_reverseSyncEnabled &&
                _reverseSyncPermissionChecked &&
                !_reverseSyncPermissionGranted) ...[
              const SizedBox(height: 8),
              const Text(
                'Notification access is required. Enable this app in Android notification access settings.',
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _openReverseSyncSettings,
                  child: const Text('Open notification access'),
                ),
              ),
            ],
            if (_reverseSyncEnabled && _reverseSyncPermissionGranted) ...[
              const SizedBox(height: 8),
              const Text(
                'Notification access granted. New phone notifications will appear on your laptop.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class WelcomeTourScreen extends StatefulWidget {
  const WelcomeTourScreen({super.key});

  @override
  State<WelcomeTourScreen> createState() => _WelcomeTourScreenState();
}

class _WelcomeTourScreenState extends State<WelcomeTourScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_TourPageData> _pages = const [
    _TourPageData(
      icon: Icons.waving_hand,
      title: 'Welcome',
      body:
          'Monitor your laptop stats and send a sleep command from your phone.',
    ),
    _TourPageData(
      icon: Icons.settings,
      title: 'Set Laptop IP',
      body:
          'Open the sidebar and go to Settings to configure your laptop IP address.',
    ),
    _TourPageData(
      icon: Icons.bolt,
      title: 'Track Live Stats',
      body:
          'The dashboard refreshes every 2 seconds and keeps a local terminal-style log.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome Tour')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          page.icon,
                          size: 80,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          page.title,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          style: const TextStyle(fontSize: 17),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Skip'),
                  ),
                  Row(
                    children: List.generate(
                      _pages.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _currentPage
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (isLastPage) {
                        Navigator.of(context).pop();
                        return;
                      }
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Text(isLastPage ? 'Finish' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourPageData {
  final IconData icon;
  final String title;
  final String body;

  const _TourPageData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class SStatusCard extends StatelessWidget {
  final double cpu;
  final double ram;
  final double temp;
  final double battery;
  final bool isPlugged;

  const SStatusCard({
    super.key,
    required this.cpu,
    required this.ram,
    required this.temp,
    required this.battery,
    required this.isPlugged,
  });

  @override
  Widget build(BuildContext context) {
    final String plugStatus = isPlugged ? ' (Charging)' : '';
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Laptop Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _StatusRow(label: 'CPU', value: '${cpu.toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            _StatusRow(label: 'RAM', value: '${ram.toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            _StatusRow(label: 'Temp', value: '${temp.toStringAsFixed(1)}°C'),
            const SizedBox(height: 8),
            _StatusRow(
              label: 'Battery',
              value: '${battery.toStringAsFixed(0)}%$plugStatus',
            ),
          ],
        ),
      ),
    );
  }
}

class LogCard extends StatelessWidget {
  final List<String> logs;
  final ScrollController scrollController;

  const LogCard({
    super.key,
    required this.logs,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF1E1E1E), // Dark background
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 250,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.terminal, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'TERMINAL LOGS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${logs.length} entries',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.green,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        logs[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFFD4D4D4), // Light grey text
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
