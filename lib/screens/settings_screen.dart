import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../providers/settings_notifier.dart';
import '../providers/riverpod_providers.dart';
import '../widgets/notification_permission_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      _ipController.text = settings.laptopIp;
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(settingsProvider);
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: kHorizontalPadding,
              vertical: kVerticalPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final notifications = ref.watch(notificationProvider);
                    if (notifications.notificationPermissionChecked &&
                        !notifications.notificationPermissionGranted) {
                      return Column(
                        children: [
                          NotificationPermissionCard(
                            onRequestPermission: () => ref
                                .read(notificationProvider.notifier)
                                .requestNotificationPermission(),
                          ),
                          const SizedBox(height: kMediumSpacing),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const Text(
                  'Connection Settings',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: kMediumSpacing),
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
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setLaptopIp(value),
                ),
                const SizedBox(height: 10),
                Text(
                  'Current target: ${settings.laptopIp}:$kDaemonPort',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Polling interval',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Slider(
                  min: SettingsState.minPollingIntervalSeconds.toDouble(),
                  max: SettingsState.maxPollingIntervalSeconds.toDouble(),
                  divisions:
                      SettingsState.maxPollingIntervalSeconds -
                      SettingsState.minPollingIntervalSeconds,
                  label: '${settings.pollingIntervalSeconds}s',
                  value: settings.pollingIntervalSeconds.toDouble(),
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setPollingInterval(value.round()),
                ),
                Text(
                  'Current interval: ${settings.pollingIntervalSeconds}s',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Reverse Sync',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: kMediumSpacing),
                _buildReverseSyncCard(ref, settings),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReverseSyncCard(WidgetRef ref, SettingsState settings) {
    return Consumer(
      builder: (context, widgetRef, _) {
        final notificationsState = ref.watch(notificationProvider);
        final notificationsNotifier = ref.watch(notificationProvider.notifier);
        if (!notificationsNotifier.isReverseSyncSupported) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Reverse sync is currently supported on Android only.',
              ),
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
                  value: settings.reverseSyncEnabled,
                  onChanged: (enabled) {
                    notificationsNotifier.setReverseSyncEnabled(
                      enabled,
                      (value) => ref
                          .read(settingsProvider.notifier)
                          .setReverseSyncEnabled(value),
                    );
                  },
                ),
                if (settings.reverseSyncEnabled &&
                    notificationsState.reverseSyncPermissionChecked &&
                    !notificationsState.reverseSyncPermissionGranted) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Notification access is required. Enable this app in Android notification access settings.',
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed:
                          notificationsNotifier.openNotificationAccessSettings,
                      child: const Text('Open notification access'),
                    ),
                  ),
                ],
                if (settings.reverseSyncEnabled &&
                    notificationsState.reverseSyncPermissionGranted) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Notification access granted. New phone notifications will appear on your laptop.',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
