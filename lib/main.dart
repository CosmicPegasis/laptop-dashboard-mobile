import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
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

class _MyHomePageState extends State<MyHomePage> {
  String laptopIp = 'localhost';
  final TextEditingController _ipController = TextEditingController(text: 'localhost');
  Timer? _timer;
  double cpu = 0.0;
  double ram = 0.0;
  double temp = 0.0;
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startTimer();
    _addLog('Dashboard started');
  }

  void _addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _logs.insert(0, '[$timestamp] $message');
      if (_logs.length > 50) _logs.removeLast();
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
      final response = await http.get(Uri.parse('http://$laptopIp:8081/stats'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          cpu = (data['cpu_usage'] as num).toDouble();
          ram = (data['ram_usage'] as num).toDouble();
          temp = (data['cpu_temp'] as num).toDouble();
        });
        // Optional: _addLog('Updated stats from $laptopIp');
      } else {
        _addLog('Error: Server returned ${response.statusCode}');
      }
    } catch (e) {
      _addLog('Connection failed: $e');
      debugPrint('Error fetching stats: $e');
    }
  }

  @override
  void dispose() {
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
                      _addLog('IP changed to $laptopIp');
                    }
                  },
                ),
              ),
              SStatusCard(cpu: cpu, ram: ram, temp: temp),
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

  const SStatusCard({
    super.key,
    required this.cpu,
    required this.ram,
    required this.temp,
  });

  @override
  Widget build(BuildContext context) {
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
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.black.withOpacity(0.05),
      child: Container(
        height: 200,
        padding: const EdgeInsets.all(12),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Event Logs',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                Text(
                  '${logs.length} entries',
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      logs[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  );
                },
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
