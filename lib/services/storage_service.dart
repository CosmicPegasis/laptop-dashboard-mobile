import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyLaptopIp = 'laptop_ip';
  static const String _keyPollingInterval = 'polling_interval_seconds';
  static const String _keyReverseSyncEnabled = 'reverse_sync_enabled';
  static const String _keyHasSeenWelcomeTour = 'has_seen_welcome_tour';
  static const String _keySeenFiles = 'seen_files';

  SharedPreferences? _prefs;
  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String> getLaptopIp() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyLaptopIp) ?? 'localhost';
  }

  Future<void> saveLaptopIp(String ip) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyLaptopIp, ip);
  }

  Future<int> getPollingInterval() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_keyPollingInterval) ?? 2;
  }

  Future<void> savePollingInterval(int seconds) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_keyPollingInterval, seconds);
  }

  Future<bool> getReverseSyncEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyReverseSyncEnabled) ?? false;
  }

  Future<void> saveReverseSyncEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyReverseSyncEnabled, enabled);
  }

  Future<bool> getHasSeenWelcomeTour() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyHasSeenWelcomeTour) ?? false;
  }

  Future<void> saveHasSeenWelcomeTour(bool seen) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyHasSeenWelcomeTour, seen);
  }

  Future<Set<String>> getSeenFiles() async {
    final prefs = await _getPrefs();
    final jsonStr = prefs.getString(_keySeenFiles);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {
      return {};
    }
    return {};
  }

  Future<void> markFileAsSeen(String filename) async {
    final prefs = await _getPrefs();
    final seen = await getSeenFiles();
    seen.add(filename);
    await prefs.setString(_keySeenFiles, json.encode(seen.toList()));
  }

  Future<void> unmarkFileAsSeen(String filename) async {
    final prefs = await _getPrefs();
    final seen = await getSeenFiles();
    seen.remove(filename);
    await prefs.setString(_keySeenFiles, json.encode(seen.toList()));
  }

  Future<void> clearSeenFiles() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keySeenFiles);
  }
}
