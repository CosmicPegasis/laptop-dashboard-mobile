import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _statsUpdateChannel = MethodChannel(
    'laptop_dashboard_mobile/stats_update',
  );

  bool _initialized = false;
  Function(String?)? _onNotificationTap;
  Function(String)? _onNotificationAction;

  Future<void> initialize({
    Function(String?)? onNotificationTap,
    Function(String)? onNotificationAction,
  }) async {
    if (_initialized) return;

    _onNotificationTap = onNotificationTap;
    _onNotificationAction = onNotificationAction;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _notificationTapBackground,
    );
    _initialized = true;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.actionId == 'download') {
      _onNotificationAction?.call('download');
    } else {
      _onNotificationTap?.call(response.payload);
    }
  }

  @pragma('vm:entry-point')
  static void _notificationTapBackground(NotificationResponse response) {
    // Handle in main isolate via notification response
  }

  Future<bool> checkAndRequestPermission() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return true;

    if (await isPermissionGranted()) return true;

    final status = await Permission.notification.request();
    return status.isGranted || await isPermissionGranted();
  }

  Future<bool> isPermissionGranted() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return true;

    if (Platform.isAndroid) {
      final androidImplementation = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImplementation != null) {
        return await androidImplementation.areNotificationsEnabled() ?? false;
      }
    }

    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<void> showOfflineNotification(int id, String laptopIp) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'laptop_offline_channel',
          'Laptop Offline',
          channelDescription: 'Notification when laptop connection is offline',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: true,
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _plugin.show(
      id,
      'Laptop Offline',
      'Cannot reach $laptopIp. We will notify again after it reconnects and goes offline later.',
      platformChannelSpecifics,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> updateForegroundService({
    required double cpu,
    required double ram,
    required double temp,
    required double battery,
    required bool isPlugged,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _statsUpdateChannel.invokeMethod('updateStats', {
        'cpu': cpu,
        'ram': ram,
        'temp': temp,
        'battery': battery,
        'isPlugged': isPlugged,
      });
    } catch (e) {
      // Log error or handle silently as in original code
    }
  }

  static const int _newFileNotificationBaseId = 100;

  Future<void> showNewFileNotification({
    required String filename,
    required int newFileCount,
    required VoidCallback onDownload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'file_download_channel',
          'File Downloads',
          channelDescription:
              'Notifications for new files available from laptop',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: false,
          icon: '@mipmap/ic_launcher',
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'download',
              'Download',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'dismiss',
              'Dismiss',
              cancelNotification: true,
            ),
          ],
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    final title = newFileCount == 1
        ? 'New File Available'
        : '$newFileCount New Files Available';
    final body = newFileCount == 1 ? filename : 'Tap to view files on laptop';

    await _plugin.show(
      _newFileNotificationBaseId,
      title,
      body,
      platformChannelSpecifics,
      payload: 'file_transfer',
    );
  }

  Future<void> cancelNewFileNotification() async {
    await _plugin.cancel(_newFileNotificationBaseId);
  }
}
