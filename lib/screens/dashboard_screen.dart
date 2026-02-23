import 'package:flutter/material.dart';
import '../widgets/status_card.dart';
import '../widgets/log_card.dart';

class DashboardScreen extends StatelessWidget {
  final double cpu;
  final double ram;
  final double temp;
  final double battery;
  final bool isPlugged;
  final List<String> logs;
  final ScrollController scrollController;
  final bool isSleeping;
  final VoidCallback onSleepPressed;

  const DashboardScreen({
    super.key,
    required this.cpu,
    required this.ram,
    required this.temp,
    required this.battery,
    required this.isPlugged,
    required this.logs,
    required this.scrollController,
    required this.isSleeping,
    required this.onSleepPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(height: 20),
            StatusCard(
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
                  onPressed: isSleeping ? null : onSleepPressed,
                  icon: isSleeping
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new),
                  label: Text(isSleeping ? 'Suspending...' : 'Sleep Laptop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade100,
                    foregroundColor: Colors.orange.shade900,
                  ),
                ),
              ),
            ),
            LogCard(logs: logs, scrollController: scrollController),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
