import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../services/reverse_sync_service.dart';
import '../widgets/notification_permission_card.dart';

class SettingsScreen extends StatefulWidget {
  final TextEditingController ipController;
  final String laptopIp;
  final int pollingIntervalSeconds;
  final int minPollingInterval;
  final int maxPollingInterval;
  final StorageService storageService;
  final NotificationService notificationService;
  final ReverseSyncService reverseSyncService;

  // Callbacks that still need to propagate to the shell / other screens
  final Function(String) onIpChanged;
  final Function(int) onPollingIntervalChanged;

  const SettingsScreen({
    super.key,
    required this.ipController,
    required this.laptopIp,
    required this.pollingIntervalSeconds,
    required this.minPollingInterval,
    required this.maxPollingInterval,
    required this.storageService,
    required this.notificationService,
    required this.reverseSyncService,
    required this.onIpChanged,
    required this.onPollingIntervalChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationPermissionGranted = false;
  bool _notificationPermissionChecked = false;
  bool _reverseSyncEnabled = false;
  bool _reverseSyncPermissionGranted = false;
  bool _reverseSyncPermissionChecked = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final reverseSyncEnabled =
        await widget.storageService.getReverseSyncEnabled();
    final notifGranted =
        await widget.notificationService.isPermissionGranted();
    final reverseSyncGranted =
        await widget.reverseSyncService.isNotificationAccessEnabled();

    if (!mounted) return;
    setState(() {
      _reverseSyncEnabled = reverseSyncEnabled;
      _notificationPermissionGranted = notifGranted;
      _notificationPermissionChecked = true;
      _reverseSyncPermissionGranted = reverseSyncGranted;
      _reverseSyncPermissionChecked = true;
    });
  }

  Future<void> _requestNotificationPermission() async {
    final granted =
        await widget.notificationService.checkAndRequestPermission();
    if (mounted) {
      setState(() => _notificationPermissionGranted = granted);
    }
  }

  Future<void> _setReverseSyncEnabled(bool enabled) async {
    if (!widget.reverseSyncService.isSupported) return;
    setState(() => _reverseSyncEnabled = enabled);
    await widget.storageService.saveReverseSyncEnabled(enabled);

    if (!enabled) {
      widget.reverseSyncService.stopListening();
    } else {
      // Re-check permission when enabling
      final granted =
          await widget.reverseSyncService.isNotificationAccessEnabled();
      if (mounted) {
        setState(() {
          _reverseSyncPermissionGranted = granted;
          _reverseSyncPermissionChecked = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_notificationPermissionChecked &&
                !_notificationPermissionGranted) ...[
              NotificationPermissionCard(
                onRequestPermission: _requestNotificationPermission,
              ),
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
              controller: widget.ipController,
              decoration: const InputDecoration(
                labelText: 'Laptop IP',
                hintText: 'e.g. 192.168.1.10',
                border: OutlineInputBorder(),
              ),
              onChanged: widget.onIpChanged,
            ),
            const SizedBox(height: 10),
            Text(
              'Current target: ${widget.laptopIp}:8081',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            const Text(
              'Polling interval',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Slider(
              min: widget.minPollingInterval.toDouble(),
              max: widget.maxPollingInterval.toDouble(),
              divisions:
                  widget.maxPollingInterval - widget.minPollingInterval,
              label: '${widget.pollingIntervalSeconds}s',
              value: widget.pollingIntervalSeconds.toDouble(),
              onChanged: (value) =>
                  widget.onPollingIntervalChanged(value.round()),
            ),
            Text(
              'Current interval: ${widget.pollingIntervalSeconds}s',
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

  Widget _buildReverseSyncCard() {
    if (!widget.reverseSyncService.isSupported) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child:
              Text('Reverse sync is currently supported on Android only.'),
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
                  onPressed:
                      widget.reverseSyncService.openNotificationAccessSettings,
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
