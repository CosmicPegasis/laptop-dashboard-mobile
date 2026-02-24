import 'dart:async';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../models/app_stats.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'settings_notifier.dart';

class StatsNotifier extends ChangeNotifier {
  final NotificationService _notificationService;

  ApiService? _apiService;
  Timer? _timer;
  int _fetchCount = 0;
  bool _isSleeping = false;
  bool _isFetchingStats = false;
  int _consecutiveFailures = 0;
  bool _offlineNotificationShown = false;
  static const int _offlineNotificationId = 1;
  static const int _maxFailuresBeforeOffline = kMaxFailuresOffline;

  AppStats _stats = AppStats(
    cpu: 0,
    ram: 0,
    temp: 0,
    battery: 0,
    isPlugged: false,
  );

  StatsNotifier({NotificationService? notificationService})
    : _notificationService = notificationService ?? NotificationService();

  AppStats get stats => _stats;
  double get cpu => _stats.cpu;
  double get ram => _stats.ram;
  double get temp => _stats.temp;
  double get battery => _stats.battery;
  bool get isPlugged => _stats.isPlugged;
  bool get isSleeping => _isSleeping;
  bool get isFetchingStats => _isFetchingStats;
  int get fetchCount => _fetchCount;
  int get consecutiveFailures => _consecutiveFailures;
  bool get isOffline => _consecutiveFailures >= _maxFailuresBeforeOffline;

  void initialize(SettingsNotifier settings) {
    _apiService = ApiService(laptopIp: settings.laptopIp);
    startTimer(settings.pollingIntervalSeconds);
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    // This will be called when settings change, but we can't use context here
    // We'll need to handle it differently - by checking the settings in main.dart
  }

  void updateFromSettings(SettingsNotifier settings) {
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
    if (_isFetchingStats || _apiService == null) return;
    _isFetchingStats = true;
    notifyListeners();

    try {
      final stats = await _apiService!.fetchStats();
      _stats = stats;
      _markOnline();
      await _updateForegroundService();
      _fetchCount++;
      notifyListeners();
    } catch (e) {
      await _markOffline(e.toString().split('\n').first);
    } finally {
      _isFetchingStats = false;
      notifyListeners();
    }
  }

  Future<void> _updateForegroundService() async {
    await _notificationService.updateForegroundService(
      cpu: _stats.cpu,
      ram: _stats.ram,
      temp: _stats.temp,
      battery: _stats.battery,
      isPlugged: _stats.isPlugged,
    );
  }

  Future<void> _markOffline(String reason) async {
    _consecutiveFailures++;
    if (_consecutiveFailures < _maxFailuresBeforeOffline) {
      return;
    }
    if (!_offlineNotificationShown && _apiService != null) {
      _offlineNotificationShown = true;
      await _notificationService.showOfflineNotification(
        _offlineNotificationId,
        _apiService!.laptopIp,
      );
    }
  }

  Future<void> _markOnline() async {
    _consecutiveFailures = 0;
    if (!_offlineNotificationShown) return;
    _offlineNotificationShown = false;
    await _notificationService.cancelNotification(_offlineNotificationId);
  }

  Future<void> sleepLaptop() async {
    if (_isSleeping || _apiService == null) return;
    _isSleeping = true;
    notifyListeners();

    try {
      await _apiService!.sleepLaptop();
    } finally {
      _isSleeping = false;
      notifyListeners();
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
