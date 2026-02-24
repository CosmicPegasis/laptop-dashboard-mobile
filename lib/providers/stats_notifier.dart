import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../models/app_stats.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'settings_notifier.dart';

class StatsState {
  final AppStats stats;
  final bool isSleeping;
  final bool isFetchingStats;
  final int fetchCount;
  final int consecutiveFailures;
  final bool offlineNotificationShown;

  StatsState({
    AppStats? stats,
    bool? isSleeping,
    bool? isFetchingStats,
    int? fetchCount,
    int? consecutiveFailures,
    bool? offlineNotificationShown,
  }) : stats =
           stats ??
           AppStats(cpu: 0, ram: 0, temp: 0, battery: 0, isPlugged: false),
       isSleeping = isSleeping ?? false,
       isFetchingStats = isFetchingStats ?? false,
       fetchCount = fetchCount ?? 0,
       consecutiveFailures = consecutiveFailures ?? 0,
       offlineNotificationShown = offlineNotificationShown ?? false;

  StatsState copyWith({
    AppStats? stats,
    bool? isSleeping,
    bool? isFetchingStats,
    int? fetchCount,
    int? consecutiveFailures,
    bool? offlineNotificationShown,
  }) {
    return StatsState(
      stats: stats ?? this.stats,
      isSleeping: isSleeping ?? this.isSleeping,
      isFetchingStats: isFetchingStats ?? this.isFetchingStats,
      fetchCount: fetchCount ?? this.fetchCount,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      offlineNotificationShown:
          offlineNotificationShown ?? this.offlineNotificationShown,
    );
  }

  double get cpu => stats.cpu;
  double get ram => stats.ram;
  double get temp => stats.temp;
  double get battery => stats.battery;
  bool get isPlugged => stats.isPlugged;
  bool get isOffline => consecutiveFailures >= kMaxFailuresOffline;
}

class StatsNotifier extends StateNotifier<StatsState> {
  final NotificationService _notificationService;
  ApiService? _apiService;
  Timer? _timer;
  static const int _offlineNotificationId = 1;

  StatsNotifier({NotificationService? notificationService})
    : _notificationService = notificationService ?? NotificationService(),
      super(StatsState());

  void updateFromSettings(SettingsState settings) {
    _apiService = ApiService(laptopIp: settings.laptopIp);
    restartTimer(settings.pollingIntervalSeconds);
  }

  void startTimer(int intervalSeconds) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _fetchStats(),
    );
  }

  void restartTimer(int intervalSeconds) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _fetchStats(),
    );
  }

  Future<void> _fetchStats() async {
    if (state.isFetchingStats || _apiService == null) return;
    state = state.copyWith(isFetchingStats: true);

    try {
      final newStats = await _apiService!.fetchStats();
      state = state.copyWith(stats: newStats, fetchCount: state.fetchCount + 1);
      await _markOnline();
      await _updateForegroundService();
    } catch (e) {
      await _markOffline(e.toString().split('\n').first);
    } finally {
      state = state.copyWith(isFetchingStats: false);
    }
  }

  Future<void> _updateForegroundService() async {
    await _notificationService.updateForegroundService(
      cpu: state.cpu,
      ram: state.ram,
      temp: state.temp,
      battery: state.battery,
      isPlugged: state.isPlugged,
    );
  }

  Future<void> _markOffline(String reason) async {
    final newFailures = state.consecutiveFailures + 1;
    state = state.copyWith(consecutiveFailures: newFailures);
    if (newFailures < kMaxFailuresOffline) return;
    if (!state.offlineNotificationShown && _apiService != null) {
      state = state.copyWith(offlineNotificationShown: true);
      await _notificationService.showOfflineNotification(
        _offlineNotificationId,
        _apiService!.laptopIp,
      );
    }
  }

  Future<void> _markOnline() async {
    if (state.consecutiveFailures == 0 || !state.offlineNotificationShown) {      
        return;
    }
    state = state.copyWith(
      consecutiveFailures: 0,
      offlineNotificationShown: false,
    );
    await _notificationService.cancelNotification(_offlineNotificationId);
  }

  Future<void> sleepLaptop() async {
    if (state.isSleeping || _apiService == null) return;
    state = state.copyWith(isSleeping: true);
    try {
      await _apiService!.sleepLaptop();
    } finally {
      state = state.copyWith(isSleeping: false);
    }
  }

  void onAppResumed(int intervalSeconds) {
    restartTimer(intervalSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
