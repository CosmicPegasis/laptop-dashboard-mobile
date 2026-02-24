import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_notifier.dart';
import 'logs_notifier.dart';
import 'upload_notifier.dart';
import 'notification_notifier.dart';
import 'stats_notifier.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);

final logsProvider = StateNotifierProvider<LogsNotifier, LogsState>(
  (ref) => LogsNotifier(),
);

final uploadProvider =
    StateNotifierProvider<UploadNotifier, UploadNotifierState>(
      (ref) => UploadNotifier(),
    );

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationNotifierState>(
      (ref) => NotificationNotifier(),
    );

final statsProvider = StateNotifierProvider<StatsNotifier, StatsState>((ref) {
  ref.watch(settingsProvider);
  return StatsNotifier();
});
