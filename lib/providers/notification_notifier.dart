import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';
import '../services/reverse_sync_service.dart';
import '../services/api_service.dart';

class NotificationNotifierState {
  final bool notificationPermissionGranted;
  final bool notificationPermissionChecked;
  final bool reverseSyncPermissionGranted;
  final bool reverseSyncPermissionChecked;

  const NotificationNotifierState({
    this.notificationPermissionGranted = false,
    this.notificationPermissionChecked = false,
    this.reverseSyncPermissionGranted = false,
    this.reverseSyncPermissionChecked = false,
  });

  NotificationNotifierState copyWith({
    bool? notificationPermissionGranted,
    bool? notificationPermissionChecked,
    bool? reverseSyncPermissionGranted,
    bool? reverseSyncPermissionChecked,
  }) {
    return NotificationNotifierState(
      notificationPermissionGranted:
          notificationPermissionGranted ?? this.notificationPermissionGranted,
      notificationPermissionChecked:
          notificationPermissionChecked ?? this.notificationPermissionChecked,
      reverseSyncPermissionGranted:
          reverseSyncPermissionGranted ?? this.reverseSyncPermissionGranted,
      reverseSyncPermissionChecked:
          reverseSyncPermissionChecked ?? this.reverseSyncPermissionChecked,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationNotifierState> {
  final NotificationService _notificationService;
  final ReverseSyncService _reverseSyncService;
  ApiService? _apiService;

  NotificationNotifier({
    NotificationService? notificationService,
    ReverseSyncService? reverseSyncService,
  }) : _notificationService = notificationService ?? NotificationService(),
       _reverseSyncService = reverseSyncService ?? ReverseSyncService(),
       super(const NotificationNotifierState());

  bool get notificationPermissionGranted => state.notificationPermissionGranted;
  bool get notificationPermissionChecked => state.notificationPermissionChecked;
  bool get reverseSyncPermissionGranted => state.reverseSyncPermissionGranted;
  bool get reverseSyncPermissionChecked => state.reverseSyncPermissionChecked;
  bool get isReverseSyncSupported => _reverseSyncService.isSupported;

  Future<void> initialize({
    required Function(String?) onNotificationTap,
    required Function(String) onNotificationAction,
  }) async {
    await _notificationService.initialize(
      onNotificationTap: onNotificationTap,
      onNotificationAction: onNotificationAction,
    );
    await _loadPermissions();
  }

  void initializeApiService(String laptopIp) {
    _apiService = ApiService(laptopIp: laptopIp);
  }

  Future<void> _loadPermissions() async {
    final notifGranted = await _notificationService.isPermissionGranted();
    final reverseSyncGranted = await _reverseSyncService
        .isNotificationAccessEnabled();

    state = state.copyWith(
      notificationPermissionGranted: notifGranted,
      notificationPermissionChecked: true,
      reverseSyncPermissionGranted: reverseSyncGranted,
      reverseSyncPermissionChecked: true,
    );
  }

  Future<bool> requestNotificationPermission() async {
    final granted = await _notificationService.checkAndRequestPermission();
    state = state.copyWith(notificationPermissionGranted: granted);
    return granted;
  }

  Future<void> setReverseSyncEnabled(
    bool enabled,
    Function(bool) onReverseSyncChanged,
  ) async {
    if (!_reverseSyncService.isSupported) return;

    onReverseSyncChanged(enabled);

    if (!enabled) {
      await _reverseSyncService.stopListening();
    } else {
      final granted = await _reverseSyncService.isNotificationAccessEnabled();
      state = state.copyWith(
        reverseSyncPermissionGranted: granted,
        reverseSyncPermissionChecked: true,
      );
    }
  }

  void openNotificationAccessSettings() {
    _reverseSyncService.openNotificationAccessSettings();
  }

  Future<void> startReverseSyncListener() async {
    if (!_reverseSyncService.isSupported || _apiService == null) return;

    _reverseSyncService.startListening(
      onEvent: (event) async {
        try {
          await _apiService!.forwardNotification(event);
        } catch (e) {
          // Silently fail
        }
      },
      onError: (e) {
        // Handle error
      },
    );
  }
}
