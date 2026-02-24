import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';
import '../services/reverse_sync_service.dart';
import '../services/api_service.dart';

class NotificationNotifier extends ChangeNotifier {
  final NotificationService _notificationService;
  final ReverseSyncService _reverseSyncService;
  ApiService? _apiService;

  bool _notificationPermissionGranted = false;
  bool _notificationPermissionChecked = false;
  bool _reverseSyncPermissionGranted = false;
  bool _reverseSyncPermissionChecked = false;

  NotificationNotifier({
    NotificationService? notificationService,
    ReverseSyncService? reverseSyncService,
  }) : _notificationService = notificationService ?? NotificationService(),
       _reverseSyncService = reverseSyncService ?? ReverseSyncService();

  bool get notificationPermissionGranted => _notificationPermissionGranted;
  bool get notificationPermissionChecked => _notificationPermissionChecked;
  bool get reverseSyncPermissionGranted => _reverseSyncPermissionGranted;
  bool get reverseSyncPermissionChecked => _reverseSyncPermissionChecked;
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

    _notificationPermissionGranted = notifGranted;
    _notificationPermissionChecked = true;
    _reverseSyncPermissionGranted = reverseSyncGranted;
    _reverseSyncPermissionChecked = true;
    notifyListeners();
  }

  Future<bool> requestNotificationPermission() async {
    final granted = await _notificationService.checkAndRequestPermission();
    _notificationPermissionGranted = granted;
    notifyListeners();
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
      _reverseSyncPermissionGranted = granted;
      _reverseSyncPermissionChecked = true;
    }
    notifyListeners();
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
