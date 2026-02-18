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
  final bool notificationPermissionChecked;
  final bool notificationPermissionGranted;
  final VoidCallback onSleepPressed;
  final VoidCallback onRequestNotificationPermission;

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
    required this.notificationPermissionChecked,
    required this.notificationPermissionGranted,
    required this.onSleepPressed,
    required this.onRequestNotificationPermission,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (notificationPermissionChecked && !notificationPermissionGranted)
              _buildNotificationPermissionCard(),
            const SizedBox(height: 20),
            const Text(
              'Hello, Aviral!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
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
                onPressed: onRequestNotificationPermission,
                child: const Text('Enable notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
