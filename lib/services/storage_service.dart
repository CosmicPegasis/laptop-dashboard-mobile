import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyLaptopIp = 'laptop_ip';
  static const String _keyPollingInterval = 'polling_interval_seconds';
  static const String _keyReverseSyncEnabled = 'reverse_sync_enabled';
  static const String _keyHasSeenWelcomeTour = 'has_seen_welcome_tour';

  Future<String> getLaptopIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLaptopIp) ?? 'localhost';
  }

  Future<void> saveLaptopIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLaptopIp, ip);
  }

  Future<int> getPollingInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPollingInterval) ?? 2;
  }

  Future<void> savePollingInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPollingInterval, seconds);
  }

  Future<bool> getReverseSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReverseSyncEnabled) ?? false;
  }

  Future<void> saveReverseSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReverseSyncEnabled, enabled);
  }

  Future<bool> getHasSeenWelcomeTour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasSeenWelcomeTour) ?? false;
  }

  Future<void> saveHasSeenWelcomeTour(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasSeenWelcomeTour, seen);
  }
}
