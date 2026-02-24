import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';

class SettingsNotifier extends ChangeNotifier {
  final StorageService _storageService;

  SettingsNotifier({StorageService? storageService})
    : _storageService = storageService ?? StorageService();

  String _laptopIp = 'localhost';
  int _pollingIntervalSeconds = 2;
  int _drawerIndex = 0;
  bool _hasSeenWelcomeTour = false;
  bool _reverseSyncEnabled = false;

  static const int minPollingIntervalSeconds = 1;
  static const int maxPollingIntervalSeconds = 30;

  String get laptopIp => _laptopIp;
  int get pollingIntervalSeconds => _pollingIntervalSeconds;
  int get drawerIndex => _drawerIndex;
  bool get hasSeenWelcomeTour => _hasSeenWelcomeTour;
  bool get reverseSyncEnabled => _reverseSyncEnabled;

  Future<void> loadSettings() async {
    _laptopIp = await _storageService.getLaptopIp();
    _pollingIntervalSeconds = await _storageService.getPollingInterval();
    _hasSeenWelcomeTour = await _storageService.getHasSeenWelcomeTour();
    _reverseSyncEnabled = await _storageService.getReverseSyncEnabled();
    notifyListeners();
  }

  Future<void> setLaptopIp(String ip) async {
    final newIp = ip.trim().isEmpty ? 'localhost' : ip.trim();
    if (newIp == _laptopIp) return;
    _laptopIp = newIp;
    await _storageService.saveLaptopIp(newIp);
    notifyListeners();
  }

  Future<void> setPollingInterval(int seconds) async {
    final normalized = seconds.clamp(
      minPollingIntervalSeconds,
      maxPollingIntervalSeconds,
    );
    if (normalized == _pollingIntervalSeconds) return;
    _pollingIntervalSeconds = normalized;
    await _storageService.savePollingInterval(normalized);
    notifyListeners();
  }

  void setDrawerIndex(int index) {
    if (_drawerIndex == index) return;
    _drawerIndex = index;
    notifyListeners();
  }

  Future<void> setHasSeenWelcomeTour(bool seen) async {
    if (_hasSeenWelcomeTour == seen) return;
    _hasSeenWelcomeTour = seen;
    await _storageService.saveHasSeenWelcomeTour(seen);
    notifyListeners();
  }

  Future<void> setReverseSyncEnabled(bool enabled) async {
    if (_reverseSyncEnabled == enabled) return;
    _reverseSyncEnabled = enabled;
    await _storageService.saveReverseSyncEnabled(enabled);
    notifyListeners();
  }
}
