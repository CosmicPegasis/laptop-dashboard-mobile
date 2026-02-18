import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final TextEditingController ipController;
  final String laptopIp;
  final int pollingIntervalSeconds;
  final int minPollingInterval;
  final int maxPollingInterval;
  final bool reverseSyncEnabled;
  final bool reverseSyncPermissionChecked;
  final bool reverseSyncPermissionGranted;
  final bool supportsReverseSync;
  final bool notificationPermissionChecked;
  final bool notificationPermissionGranted;

  final Function(String) onIpChanged;
  final Function(int) onPollingIntervalChanged;
  final Function(bool) onReverseSyncChanged;
  final VoidCallback onOpenReverseSyncSettings;
  final VoidCallback onRequestNotificationPermission;

  const SettingsScreen({
    super.key,
    required this.ipController,
    required this.laptopIp,
    required this.pollingIntervalSeconds,
    required this.minPollingInterval,
    required this.maxPollingInterval,
    required this.reverseSyncEnabled,
    required this.reverseSyncPermissionChecked,
    required this.reverseSyncPermissionGranted,
    required this.supportsReverseSync,
    required this.notificationPermissionChecked,
    required this.notificationPermissionGranted,
    required this.onIpChanged,
    required this.onPollingIntervalChanged,
    required this.onReverseSyncChanged,
    required this.onOpenReverseSyncSettings,
    required this.onRequestNotificationPermission,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notificationPermissionChecked && !notificationPermissionGranted) ...[
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
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'Laptop IP',
                hintText: 'e.g. 192.168.1.10',
                border: OutlineInputBorder(),
              ),
              onChanged: onIpChanged,
            ),
            const SizedBox(height: 10),
            Text(
              'Current target: $laptopIp:8081',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            const Text(
              'Polling interval',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Slider(
              min: minPollingInterval.toDouble(),
              max: maxPollingInterval.toDouble(),
              divisions: maxPollingInterval - minPollingInterval,
              label: '${pollingIntervalSeconds}s',
              value: pollingIntervalSeconds.toDouble(),
              onChanged: (value) => onPollingIntervalChanged(value.round()),
            ),
            Text(
              'Current interval: ${pollingIntervalSeconds}s',
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
                onPressed: onRequestNotificationPermission,
                child: const Text('Enable notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReverseSyncCard() {
    if (!supportsReverseSync) {
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
              value: reverseSyncEnabled,
              onChanged: onReverseSyncChanged,
            ),
            if (reverseSyncEnabled &&
                reverseSyncPermissionChecked &&
                !reverseSyncPermissionGranted) ...[
              const SizedBox(height: 8),
              const Text(
                'Notification access is required. Enable this app in Android notification access settings.',
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onOpenReverseSyncSettings,
                  child: const Text('Open notification access'),
                ),
              ),
            ],
            if (reverseSyncEnabled && reverseSyncPermissionGranted) ...[
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
