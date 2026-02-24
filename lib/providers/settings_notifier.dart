import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';

class SettingsState {
  final String laptopIp;
  final int pollingIntervalSeconds;
  final int drawerIndex;
  final bool hasSeenWelcomeTour;
  final bool reverseSyncEnabled;

  static const int minPollingIntervalSeconds = 1;
  static const int maxPollingIntervalSeconds = 30;

  SettingsState({
    this.laptopIp = 'localhost',
    this.pollingIntervalSeconds = 2,
    this.drawerIndex = 0,
    this.hasSeenWelcomeTour = false,
    this.reverseSyncEnabled = false,
  });

  SettingsState copyWith({
    String? laptopIp,
    int? pollingIntervalSeconds,
    int? drawerIndex,
    bool? hasSeenWelcomeTour,
    bool? reverseSyncEnabled,
  }) {
    return SettingsState(
      laptopIp: laptopIp ?? this.laptopIp,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      drawerIndex: drawerIndex ?? this.drawerIndex,
      hasSeenWelcomeTour: hasSeenWelcomeTour ?? this.hasSeenWelcomeTour,
      reverseSyncEnabled: reverseSyncEnabled ?? this.reverseSyncEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final StorageService _storageService;

  SettingsNotifier({StorageService? storageService})
    : _storageService = storageService ?? StorageService(),
      super(SettingsState());

  Future<void> loadSettings() async {
    final ip = await _storageService.getLaptopIp();
    final polling = await _storageService.getPollingInterval();
    final tour = await _storageService.getHasSeenWelcomeTour();
    final reverse = await _storageService.getReverseSyncEnabled();
    state = state.copyWith(
      laptopIp: ip,
      pollingIntervalSeconds: polling,
      hasSeenWelcomeTour: tour,
      reverseSyncEnabled: reverse,
    );
  }

  Future<void> setLaptopIp(String ip) async {
    final newIp = ip.trim().isEmpty ? 'localhost' : ip.trim();
    if (newIp == state.laptopIp) return;
    state = state.copyWith(laptopIp: newIp);
    await _storageService.saveLaptopIp(newIp);
  }

  Future<void> setPollingInterval(int seconds) async {
    final normalized = seconds.clamp(
      SettingsState.minPollingIntervalSeconds,
      SettingsState.maxPollingIntervalSeconds,
    );
    if (normalized == state.pollingIntervalSeconds) return;
    state = state.copyWith(pollingIntervalSeconds: normalized);
    await _storageService.savePollingInterval(normalized);
  }

  void setDrawerIndex(int index) {
    if (state.drawerIndex == index) return;
    state = state.copyWith(drawerIndex: index);
  }

  Future<void> setHasSeenWelcomeTour(bool seen) async {
    if (state.hasSeenWelcomeTour == seen) return;
    state = state.copyWith(hasSeenWelcomeTour: seen);
    await _storageService.saveHasSeenWelcomeTour(seen);
  }

  Future<void> setReverseSyncEnabled(bool enabled) async {
    if (state.reverseSyncEnabled == enabled) return;
    state = state.copyWith(reverseSyncEnabled: enabled);
    await _storageService.saveReverseSyncEnabled(enabled);
  }
}
