import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  String laptopIp = 'localhost';
  final TextEditingController _ipController = TextEditingController(text: 'localhost');
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

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLaptopIp();
    _initializeNotifications();
    _startTimer();
    _addLog('Dashboard started');
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

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _showPersistentNotification() async {
    final String plugStatus = isPlugged ? 'Charging' : 'Discharging';
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
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
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Laptop Status: ${battery.toStringAsFixed(0)}% ($plugStatus)',
      'CPU: ${cpu.toStringAsFixed(1)}% | RAM: ${ram.toStringAsFixed(1)}%',
      platformChannelSpecifics,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _addLog('App State: ${state.name}');
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else if (state == AppLifecycleState.paused) {
      // Keep timer running in background if we want persistent updates
      // _timer?.cancel(); 
    }
  }

  void _addLog(String message) {
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
    try {
      final response = await http.get(Uri.parse('http://$laptopIp:8081/stats')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newCpu = (data['cpu_usage'] ?? 0.0) as num;
        final newRam = (data['ram_usage'] ?? 0.0) as num;
        final newTemp = (data['cpu_temp'] ?? 0.0) as num;
        final newBattery = (data['battery_percent'] ?? 0.0) as num;
        final newPlugged = (data['is_plugged'] ?? false) as bool;
        
        bool valuesChanged = newCpu.toDouble() != cpu || 
                            newRam.toDouble() != ram || 
                            newTemp.toDouble() != temp || 
                            newBattery.toDouble() != battery || 
                            newPlugged != isPlugged;
        
        setState(() {
          cpu = newCpu.toDouble();
          ram = newRam.toDouble();
          temp = newTemp.toDouble();
          battery = newBattery.toDouble();
          isPlugged = newPlugged;
        });
        
        _showPersistentNotification();

        _fetchCount++;
        if (valuesChanged || _fetchCount % 5 == 0) {
          String reason = valuesChanged ? 'values changed' : 'periodic sync';
          _addLog('Stats updated ($reason)');
        }
      } else {
        _addLog('Error: Server returned ${response.statusCode}');
      }
    } on TimeoutException {
      _addLog('Connection timeout to $laptopIp');
    } catch (e) {
      _addLog('Connection failed: ${e.toString().split('\n').first}');
      debugPrint('Error fetching stats: $e');
    }
  }

  Future<void> _sleepLaptop() async {
    setState(() => _isSleeping = true);
    try {
      final response = await http.post(Uri.parse('http://$laptopIp:8081/sleep')).timeout(const Duration(seconds: 5));
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
        content: const Text('Are you sure you want to put your laptop to sleep? You will lose connection until it wakes up.'),
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
    _ipController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laptop Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 20),
              const Text(
                'Hello, Aviral!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                child: TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Laptop IP',
                    hintText: 'e.g. 192.168.1.10',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final newIp = value.trim().isEmpty ? 'localhost' : value.trim();
                    if (newIp != laptopIp) {
                      setState(() {
                        laptopIp = newIp;
                      });
                      _saveLaptopIp(newIp);
                      _addLog('IP changed to $laptopIp');
                    }
                  },
                ),
              ),
              SStatusCard(cpu: cpu, ram: ram, temp: temp, battery: battery, isPlugged: isPlugged),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: _isSleeping ? null : () => _showSleepConfirmation(context),
                    icon: _isSleeping 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
      ),
    );
  }
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
            _StatusRow(label: 'Battery', value: '${battery.toStringAsFixed(0)}%$plugStatus'),
          ],
        ),
      ),
    );
  }
}

class LogCard extends StatelessWidget {
  final List<String> logs;
  final ScrollController scrollController;

  const LogCard({super.key, required this.logs, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF1E1E1E), // Dark background
      clipBehavior: Clip.antiAlias,
      child: Container(
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
